import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var trialPlayer: AVAudioPlayer?
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
            self.stopTrialAudio()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: typed.data)
            self.trialPlayer = player
            guard player.prepareToPlay(), player.play() else {
              throw NSError(domain: "KoF5TrialAudio", code: 1)
            }
            result(nil)
          } catch {
            self.stopTrialAudio()
            result(FlutterError(code: "play_failed", message: "Could not play trial MP3", details: nil))
          }
        case "stop":
          self.stopTrialAudio()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      trialChannel = channel
      backgroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.stopTrialAudio() }
    }
  }

  private func stopTrialAudio() {
    trialPlayer?.stop()
    trialPlayer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  deinit {
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
  }
}
