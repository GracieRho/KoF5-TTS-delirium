import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../device_anonymous_auth.dart';
import '../models/bedside_status.dart';
import '../models/runtime_state.dart';
import '../services/runtime_config.dart';
import '../services/runtime_hospital_message.dart';
import '../synthetic_auxiliary_alert.dart';
import '../synthetic_hospital_message.dart';
import '../trial_audio_player.dart';

typedef HospitalPoller = Future<RuntimeHospitalMessage?> Function();
typedef MessagePlayer = Future<bool> Function(RuntimeHospitalMessage message);

class PatientRuntimeController extends ValueNotifier<RuntimeState> {
  PatientRuntimeController({
    RuntimeConfig config = RuntimeConfig.environment,
    HospitalPoller? pollHospital,
    MessagePlayer? playMessage,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _config = config,
       _pollHospitalOverride = pollHospital,
       _playMessageOverride = playMessage,
       _pollInterval = pollInterval,
       super(
         const RuntimeState(
           status: BedsideStatus.waiting,
           message: '확인된 병실 안내가 아직 없습니다.',
         ),
       );

  final RuntimeConfig _config;
  final HospitalPoller? _pollHospitalOverride;
  final MessagePlayer? _playMessageOverride;
  final Duration _pollInterval;
  final TrialAudioPlayer _player = TrialAudioPlayer();
  Timer? _pollTimer;
  HttpClient? _client;
  AnonymousDeviceSession? _session;
  var _busy = false;
  var _disposed = false;

  Future<void> start() async {
    if (_disposed || _pollTimer != null) return;
    value = const RuntimeState(
      status: BedsideStatus.waiting,
      message: '확인된 병실 안내가 아직 없습니다.',
    );
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => unawaited(_pollHospitalMessage()),
    );
    await _pollHospitalMessage();
  }

  Future<void> _pollHospitalMessage() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      final message = _pollHospitalOverride != null
          ? await _pollHospitalOverride()
          : await _pollCloudHospitalMessage();
      if (_disposed || message == null) return;
      value = RuntimeState(
        status: BedsideStatus.playing,
        message: message.text,
      );
      final completed = _playMessageOverride != null
          ? await _playMessageOverride(message)
          : await _playAndConfirm(message);
      if (!_disposed) {
        value = RuntimeState(
          status: BedsideStatus.waiting,
          message: completed ? message.text : '안내 말씀을 다시 준비하고 있습니다.',
        );
      }
    } catch (_) {
      _setResting('병원 안내 연결을 잠시 확인하고 있습니다.');
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
    _client?.close(force: true);
    super.dispose();
  }
}
