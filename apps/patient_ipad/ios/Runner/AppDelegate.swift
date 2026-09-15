import AVFoundation
import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var trialPlayer: AVAudioPlayer?
  private var trialSessionActive = false
  private var trialChannel: FlutterMethodChannel?
  private var speechChannel: FlutterMethodChannel?
  private let koreanRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
  private var speechTask: SFSpeechRecognitionTask?
  private var speechResult: FlutterResult?
  private var speechGeneration = 0
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
      ) { [weak self] _ in
        _ = self?.stopTrialAudio()
        self?.cancelSpeech()
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KoF5OnDeviceSpeech") {
      let channel = FlutterMethodChannel(name: "kof5/on_device_speech", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(FlutterMethodNotImplemented); return }
        switch call.method {
        case "available":
          result(self.koreanRecognizer?.supportsOnDeviceRecognition == true
            && self.koreanRecognizer?.isAvailable == true)
        case "authorize":
          guard self.koreanRecognizer?.supportsOnDeviceRecognition == true else {
            result(false)
            return
          }
          if SFSpeechRecognizer.authorizationStatus() == .authorized {
            result(true)
          } else if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { status in
              DispatchQueue.main.async { result(status == .authorized) }
            }
          } else {
            result(false)
          }
        case "transcribe":
          self.transcribeOnDevice(call.arguments, result: result)
        case "cancel":
          self.cancelSpeech()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      speechChannel = channel
    }
  }

  private func transcribeOnDevice(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let data = (arguments as? FlutterStandardTypedData)?.data,
          !data.isEmpty, data.count.isMultiple(of: 2), data.count <= 16_000 * 2 * 8,
          SFSpeechRecognizer.authorizationStatus() == .authorized,
          let recognizer = koreanRecognizer, recognizer.supportsOnDeviceRecognition,
          recognizer.isAvailable, speechTask == nil else {
      result(FlutterError(code: "speech_unavailable", message: "On-device Korean recognition unavailable", details: nil))
      return
    }
    let frames = data.count / 2
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
          let channel = buffer.floatChannelData?.pointee else {
      result(FlutterError(code: "speech_format", message: "Could not prepare bounded PCM", details: nil))
      return
    }
    buffer.frameLength = AVAudioFrameCount(frames)
    data.withUnsafeBytes { bytes in
      for frame in 0..<frames {
        let bits = UInt16(bytes[frame * 2]) | (UInt16(bytes[frame * 2 + 1]) << 8)
        channel[frame] = Float(Int16(bitPattern: bits)) / 32_768
      }
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.append(buffer)
    request.endAudio()
    speechGeneration += 1
    let generation = speechGeneration
    speechResult = result
    speechTask = recognizer.recognitionTask(with: request) { [weak self] recognized, error in
      DispatchQueue.main.async {
        guard let self, self.speechGeneration == generation else { return }
        if let recognized, recognized.isFinal {
          let transcript = recognized.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
          self.finishSpeech(transcript.isEmpty ? nil : transcript)
        } else if error != nil {
          self.finishSpeech(nil)
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self, self.speechGeneration == generation else { return }
      self.cancelSpeech()
    }
  }

  private func finishSpeech(_ transcript: String?) {
    speechGeneration += 1
    speechTask = nil
    let result = speechResult
    speechResult = nil
    result?(transcript)
  }

  private func cancelSpeech() {
    speechGeneration += 1
    speechTask?.cancel()
    speechTask = nil
    let result = speechResult
    speechResult = nil
    result?(nil)
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
    cancelSpeech()
  }
}
