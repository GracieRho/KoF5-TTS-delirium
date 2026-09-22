import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../device_anonymous_auth.dart';
import '../models/approved_bedside_data.dart';
import '../models/bedside_context.dart';
import '../models/bedside_status.dart';
import '../models/runtime_state.dart';
import '../services/approved_bedside_context.dart';
import '../services/runtime_config.dart';
import '../services/runtime_hospital_message.dart';
import '../synthetic_auxiliary_alert.dart';
import '../synthetic_hospital_message.dart';
import '../trial_audio_player.dart';

typedef HospitalPoller = Future<RuntimeHospitalMessage?> Function();
typedef MessagePlayer = Future<bool> Function(RuntimeHospitalMessage message);
typedef BedsideDataLoader = Future<ApprovedBedsideData?> Function();

class PatientRuntimeController extends ValueNotifier<RuntimeState> {
  PatientRuntimeController({
    RuntimeConfig config = RuntimeConfig.environment,
    BedsideDataLoader? loadBedsideData,
    HospitalPoller? pollHospital,
    MessagePlayer? playMessage,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _config = config,
       _loadBedsideDataOverride = loadBedsideData,
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
  final BedsideDataLoader? _loadBedsideDataOverride;
  final HospitalPoller? _pollHospitalOverride;
  final MessagePlayer? _playMessageOverride;
  final Duration _pollInterval;
  final TrialAudioPlayer _player = TrialAudioPlayer();
  Timer? _pollTimer;
  HttpClient? _client;
  AnonymousDeviceSession? _session;
  DevicePairContext? _pair;
  var _busy = false;
  var _disposed = false;

  Future<void> start() async {
    if (_disposed || _pollTimer != null) return;
    value = const RuntimeState(
      status: BedsideStatus.waiting,
      message: '확인된 병실 안내가 아직 없습니다.',
      context: BedsideContext.unverified,
      schedule: [],
    );
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      final bedside = _loadBedsideDataOverride != null
          ? await _loadBedsideDataOverride()
          : await _loadCloudBedsideData();
      if (_disposed) return;
      _setBedsideData(bedside);
    } catch (_) {
      _clearBedsideData();
      _busy = false;
      return;
    }
    try {
      final message = _pollHospitalOverride != null
          ? await _pollHospitalOverride()
          : await _pollCloudHospitalMessage();
      if (_disposed || message == null) return;
      value = RuntimeState(
        status: BedsideStatus.playing,
        message: message.text,
        context: value.context,
        schedule: value.schedule,
      );
      final completed = _playMessageOverride != null
          ? await _playMessageOverride(message)
          : await _playAndConfirm(message);
      if (!_disposed) {
        value = RuntimeState(
          status: BedsideStatus.waiting,
          message: completed ? message.text : '안내 말씀을 다시 준비하고 있습니다.',
          context: value.context,
          schedule: value.schedule,
        );
      }
    } catch (_) {
      _setResting('병원 안내 연결을 잠시 확인하고 있습니다.', keepBedsideData: true);
    } finally {
      _busy = false;
    }
  }

  Future<ApprovedBedsideData?> _loadCloudBedsideData() async {
    if (!_config.cloudReady) return null;
    final connection = await _ensureDeviceConnection();
    return fetchApprovedBedsideData(
      connection.$1,
      Uri.parse(_config.supabaseUrl),
      _config.publishableKey,
      connection.$2,
      connection.$3,
    );
  }

  Future<RuntimeHospitalMessage?> _pollCloudHospitalMessage() async {
    if (!_config.cloudReady) return null;
    final project = Uri.parse(_config.supabaseUrl);
    final origin = Uri.parse(_config.apiOrigin);
    final connection = await _ensureDeviceConnection();
    final client = connection.$1;
    final session = connection.$2;
    final ids = await listSyntheticDueHospitalMessageIds(
      client,
      project,
      _config.publishableKey,
      session,
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

  Future<(HttpClient, AnonymousDeviceSession, DevicePairContext)>
  _ensureDeviceConnection() async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    var session = _session;
    var pair = _pair;
    if (session?.usable(DateTime.now()) != true || pair == null) {
      session = await signInAnonymousDevice(
        client,
        Uri.parse(_config.supabaseUrl),
        _config.publishableKey,
      );
      pair = await confirmSyntheticDevicePair(
        client,
        Uri.parse(_config.supabaseUrl),
        _config.publishableKey,
        session,
      );
      if (pair.patientId != syntheticPatientId) {
        throw const FormatException('확인된 합성 기기 연결이 필요합니다.');
      }
      _session = session;
      _pair = pair;
    }
    return (client, session!, pair);
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

  void _setBedsideData(ApprovedBedsideData? bedside) {
    value = RuntimeState(
      status: value.status,
      message: bedside == null ? '확인된 병실 안내가 아직 없습니다.' : value.message,
      context: bedside?.context ?? BedsideContext.unverified,
      schedule: bedside?.schedule ?? const [],
    );
  }

  void _clearBedsideData() => _setBedsideData(null);

  void _setResting(String message, {bool keepBedsideData = false}) {
    if (!_disposed) {
      value = RuntimeState(
        status: BedsideStatus.resting,
        message: message,
        context: keepBedsideData ? value.context : BedsideContext.unverified,
        schedule: keepBedsideData ? value.schedule : const [],
      );
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
