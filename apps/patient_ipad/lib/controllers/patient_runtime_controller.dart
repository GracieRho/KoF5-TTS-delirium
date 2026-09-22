import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../device_anonymous_auth.dart';
import '../models/bedside_status.dart';
import '../models/runtime_state.dart';
import '../speech_candidate.dart';
import '../synthetic_auxiliary_alert.dart';
import '../synthetic_hospital_message.dart';
import '../trial_audio_player.dart';
import '../services/runtime_config.dart';
import '../services/runtime_hospital_message.dart';

typedef CaptureStarter = Future<Stream<Uint8List>> Function();
typedef CaptureStopper = Future<void> Function();
typedef HospitalPoller = Future<RuntimeHospitalMessage?> Function();
typedef MessagePlayer = Future<bool> Function(RuntimeHospitalMessage message);

class PatientRuntimeController extends ValueNotifier<RuntimeState> {
  PatientRuntimeController({
    RuntimeConfig config = RuntimeConfig.environment,
    CaptureStarter? startCapture,
    CaptureStopper? stopCapture,
    HospitalPoller? pollHospital,
    MessagePlayer? playMessage,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _config = config,
       _startCaptureOverride = startCapture,
       _stopCaptureOverride = stopCapture,
       _pollHospitalOverride = pollHospital,
       _playMessageOverride = playMessage,
       _pollInterval = pollInterval,
       super(
         const RuntimeState(
           status: BedsideStatus.listening,
           message: '병실 안내를 준비하고 있습니다.',
         ),
       );

  final RuntimeConfig _config;
  final CaptureStarter? _startCaptureOverride;
  final CaptureStopper? _stopCaptureOverride;
  final HospitalPoller? _pollHospitalOverride;
  final MessagePlayer? _playMessageOverride;
  final Duration _pollInterval;
  AudioRecorder? _recorder;
  final SpeechCandidateDetector _detector = SpeechCandidateDetector();
  final TrialAudioPlayer _player = TrialAudioPlayer();
  StreamSubscription<Uint8List>? _capture;
  Timer? _pollTimer;
  HttpClient? _client;
  AnonymousDeviceSession? _session;
  var _busy = false;
  var _disposed = false;

  Future<void> start() async {
    if (_disposed || _capture != null) return;
    try {
      final stream = _startCaptureOverride != null
          ? await _startCaptureOverride()
          : await _startRecorder();
      if (_disposed) return;
      _detector.reset();
      _capture = stream.listen(
        _onAudio,
        onError: (_) => _setResting('병실 안내를 잠시 준비하고 있습니다.'),
      );
      value = const RuntimeState(
        status: BedsideStatus.listening,
        message: '오늘 일정과 병실 안내를 확인할 수 있습니다.',
      );
      _pollTimer ??= Timer.periodic(
        _pollInterval,
        (_) => unawaited(_pollHospitalMessage()),
      );
      unawaited(_pollHospitalMessage());
    } catch (_) {
      _setResting('병실 안내를 잠시 준비하고 있습니다.');
    }
  }

  Future<Stream<Uint8List>> _startRecorder() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('microphone permission unavailable');
    }
    return recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        streamBufferSize: 3200,
      ),
    );
  }

  void _onAudio(Uint8List pcm) {
    _detector.add(pcm); // Local VAD stays active; audio is not retained here.
  }

  Future<void> _pollHospitalMessage() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      final message = _pollHospitalOverride != null
          ? await _pollHospitalOverride()
          : await _pollCloudHospitalMessage();
      if (_disposed || message == null) return;
      await _pauseCapture();
      value = RuntimeState(
        status: BedsideStatus.playing,
        message: message.text,
      );
      final completed = _playMessageOverride != null
          ? await _playMessageOverride(message)
          : await _playAndConfirm(message);
      if (!_disposed) {
        value = RuntimeState(
          status: BedsideStatus.listening,
          message: completed ? message.text : '안내 말씀을 다시 준비하고 있습니다.',
        );
        await start();
      }
    } catch (_) {
      if (!_disposed && _capture == null) await start();
    } finally {
      _busy = false;
    }
  }

  Future<RuntimeHospitalMessage?> _pollCloudHospitalMessage() async {
    if (!_config.cloudReady) return null;
    final project = Uri.parse(_config.supabaseUrl);
    final origin = Uri.parse(_config.apiOrigin);
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    var session = _session;
    if (session?.usable(DateTime.now()) != true) {
      session = await signInAnonymousDevice(
        client,
        project,
        _config.publishableKey,
      );
      final pair = await confirmSyntheticDevicePair(
        client,
        project,
        _config.publishableKey,
        session,
      );
      if (pair.patientId != syntheticPatientId) return null;
      _session = session;
    }
    final ids = await listSyntheticDueHospitalMessageIds(
      client,
      project,
      _config.publishableKey,
      session!,
    );
    if (ids.isEmpty) return null;
    final approved = await confirmSyntheticDueHospitalMessage(
      client,
      project,
      _config.publishableKey,
      session,
      ids.first,
    );
    final endpoint = origin.replace(
      path:
          '/internal/synthetic/paired/$syntheticPatientId/message/${approved.id}/audio',
    );
    final audio = await synthesizeSyntheticHospitalMessage(
      client,
      endpoint,
      _config.internalToken,
      session,
      approved,
    );
    return RuntimeHospitalMessage(
      id: approved.id,
      text: approved.approvedText,
      audio: audio,
    );
  }

  Future<bool> _playAndConfirm(RuntimeHospitalMessage message) async {
    await _player.play(message.audio);
    final finished = await _player.waitFinished();
    final session = _session;
    final client = _client;
    if (!finished || session == null || client == null) return false;
    return completeSyntheticHospitalPlayback(
      client,
      Uri.parse(_config.supabaseUrl),
      _config.publishableKey,
      session,
      message.id,
      newSyntheticAlertIdempotencyKey(),
    );
  }

  Future<void> _pauseCapture() async {
    final capture = _capture;
    _capture = null;
    await capture?.cancel();
    if (_stopCaptureOverride != null) {
      await _stopCaptureOverride();
    } else {
      await _recorder?.stop();
    }
    _detector.reset();
  }

  void _setResting(String message) {
    if (!_disposed) {
      value = RuntimeState(status: BedsideStatus.resting, message: message);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(_capture?.cancel());
    _capture = null;
    if (_startCaptureOverride == null && _recorder != null) {
      unawaited(_recorder!.dispose());
    }
    _client?.close(force: true);
    super.dispose();
  }
}
