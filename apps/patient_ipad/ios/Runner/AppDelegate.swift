import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var trialPlayer: AVAudioPlayer?
  private var trialSessionActive = false
  private var trialChannel: FlutterMethodChannel?
  private var backgroundObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KoF5TrialAudio") {
      let channel = FlutterMethodChannel(name: "kof5/trial_audio", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(FlutterMethodNotImplemented); return }
        switch call.method {
        case "play":
          guard let typed = call.arguments as? FlutterStandardTypedData,
                !typed.data.isEmpty, typed.data.count <= 2_000_000 else {
            result(FlutterError(code: "invalid_audio", message: "Bounded MP3 data required", details: nil))
            return
          }
          do {
            guard self.stopTrialAudio() else { throw NSError(domain: "KoF5TrialAudio", code: 2) }
            let player = try AVAudioPlayer(data: typed.data)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            self.trialSessionActive = true
            self.trialPlayer = player
            guard player.prepareToPlay(), player.play() else {
              throw NSError(domain: "KoF5TrialAudio", code: 1)
            }
            result(nil)
          } catch {
            _ = self.stopTrialAudio()
            result(FlutterError(code: "play_failed", message: "Could not play trial MP3", details: nil))
          }
        case "stop":
          if self.stopTrialAudio() {
            result(nil)
          } else {
            result(FlutterError(code: "stop_unconfirmed", message: "Could not deactivate trial playback", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      trialChannel = channel
      backgroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in _ = self?.stopTrialAudio() }
    }
  }

  @discardableResult private func stopTrialAudio() -> Bool {
    trialPlayer?.stop()
    trialPlayer = nil
    guard trialSessionActive else { return true }
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      trialSessionActive = false
      return true
    } catch {
      return false
    }
  }

  deinit {
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
  }
}
