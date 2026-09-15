import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'speech_candidate.dart';
import 'synthetic_cloud_trial.dart';
import 'trial_audio_player.dart';

void main() => runApp(const PatientMicDemo());

class PatientMicDemo extends StatefulWidget {
  const PatientMicDemo({super.key});

  @override
  State<PatientMicDemo> createState() => _PatientMicDemoState();
}

class _PatientMicDemoState extends State<PatientMicDemo>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _detector = SpeechCandidateDetector();
  final _player = TrialAudioPlayer();
  final _endpoint = TextEditingController();
  final _token = TextEditingController();
  StreamSubscription<Uint8List>? _subscription;
  Timer? _candidateExpiry;
  HttpClient? _cloudClient;
  Uint8List? _heldCandidate;
  var _listening = false;
  var _starting = false;
  var _stopping = false;
  var _foreground = true;
  var _stopUnconfirmed = false;
  var _candidateCount = 0;
  var _status = '마이크 시험을 시작할 수 있습니다.';
  var _ownVoiceTrial = false;
  var _sending = false;
  var _playedReply = false;
  var _trialGeneration = 0;
  var _cloudStatus = '자가 음성 시험을 확인하면 발화 후보 한 건을 직접 보낼 수 있습니다.';
  var _cloudTranscript = '';
  var _cloudReply = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _discardTrial();
      _stop();
    }
  }

  void _discardTrial() {
    _trialGeneration++;
    _cloudClient?.close(force: true);
    _cloudClient = null;
    unawaited(_player.stop().catchError((_) {}));
    _token.clear();
    _candidateExpiry?.cancel();
    _candidateExpiry = null;
    _heldCandidate = null;
    _ownVoiceTrial = false;
    _sending = false;
    _playedReply = false;
    if (mounted) {
      setState(() {
        _cloudStatus = '시험 자료를 폐기했습니다.';
        _cloudTranscript = '';
        _cloudReply = '';
      });
    }
  }

  Future<void> _start() async {
    if (_starting ||
        _stopping ||
        _listening ||
        _sending ||
        _stopUnconfirmed ||
        !_foreground) {
      return;
    }
    setState(() => _starting = true);
    try {
      if (_playedReply && !await _stopReply()) return;
      if (!await _recorder.hasPermission()) {
        if (mounted) setState(() => _status = '마이크 권한이 필요합니다.');
        return;
      }
      if (!mounted || !_foreground) return;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          streamBufferSize: 3200,
        ),
      );
      if (!mounted || !_foreground) {
        _subscription = stream.listen((_) {}); // Discard any late PCM.
        _listening = true;
        await _stop();
        return;
      }
      _detector.reset();
      _subscription = stream.listen(
        _onAudio,
        onError: (Object error) {
          _stop().then((_) {
            if (mounted && !_stopUnconfirmed) {
              setState(() => _status = '마이크 입력이 중단됐습니다.');
            }
          });
        },
      );
      setState(() {
        _listening = true;
        _status = '기기에서 발화 후보를 감지하는 중입니다.';
      });
    } catch (_) {
      if (mounted) setState(() => _status = '마이크를 시작할 수 없습니다.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<bool> _stopReply() async {
    try {
      await _player.stop();
      if (mounted) {
        setState(() {
          _playedReply = false;
          _cloudStatus = '음성 응답 재생을 중단했습니다.';
        });
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _cloudStatus = '음성 응답 중단을 확인하지 못했습니다.');
      return false;
    }
  }

  void _onAudio(Uint8List pcm) {
    if (!mounted || !_foreground || !_listening) return;
    final candidate = _detector.add(pcm);
    if (candidate == null || !mounted) return;
    // Only an explicit self-voice trial may retain one candidate for manual upload.
    setState(() {
      _candidateCount++;
      _candidateExpiry?.cancel();
      _heldCandidate = _ownVoiceTrial ? candidate : null;
      _status = '발화 후보 $_candidateCount건 감지 · 자동 전송 없음';
      if (_heldCandidate != null) {
        _cloudStatus = '자가 음성 후보 한 건 준비 · 30초 내 직접 전송 가능';
        _candidateExpiry = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() {
              _heldCandidate = null;
              _cloudStatus = '후보 보관 시간이 지나 오디오를 폐기했습니다.';
            });
          }
        });
      }
    });
  }

  Future<void> _sendTrial() async {
    if (!_ownVoiceTrial ||
        _heldCandidate == null ||
        _sending ||
        _stopping ||
        !_foreground) {
      return;
    }
    final generation = ++_trialGeneration;
    final pcm = _heldCandidate!;
    _candidateExpiry?.cancel();
    _candidateExpiry = null;
    _heldCandidate = null;
    setState(() {
      _sending = true;
      _cloudStatus = '마이크 중단 확인 중입니다.';
      _cloudTranscript = '';
      _cloudReply = '';
    });
    await _stop();
    if (!mounted ||
        !_foreground ||
        !_ownVoiceTrial ||
        generation != _trialGeneration) {
      return;
    }
    if (_stopUnconfirmed || _stopping || _listening) {
      setState(() {
        _sending = false;
        _cloudStatus = '마이크 중단을 확인하지 못해 전송하지 않았습니다.';
      });
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _cloudClient = client;
    try {
      final endpoint = Uri.parse(_endpoint.text.trim());
      final result = await sendOwnVoiceCandidate(
        client,
        endpoint,
        _token.text,
        pcm,
      ).timeout(const Duration(seconds: 70));
      if (!mounted || !_foreground || generation != _trialGeneration) return;
      setState(() {
        _cloudTranscript = result.transcript;
        _cloudReply = result.reply ?? '';
        _cloudStatus = result.mp3 == null
            ? '서버 안전 경로에서 음성 응답을 만들지 않았습니다.'
            : '클라우드 자가 음성 시험 응답 · 재생 시작';
      });
      if (result.mp3 != null) {
        await _player.play(result.mp3!);
        if (!_foreground || generation != _trialGeneration) {
          await _player.stop();
        } else {
          setState(() => _playedReply = true);
        }
      }
    } catch (_) {
      if (mounted && _foreground && generation == _trialGeneration) {
        setState(() => _cloudStatus = '전송·처리에 실패했습니다. 주소와 내부 시험 설정을 확인하세요.');
      }
    } finally {
      client.close(force: true);
      if (_cloudClient == client) _cloudClient = null;
      if (mounted && generation == _trialGeneration) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _stop() async {
    if (_stopping || (!_listening && _subscription == null)) return;
    _stopping = true;
    _listening = false;
    _detector.reset();
    _candidateExpiry?.cancel();
    _candidateExpiry = null;
    _heldCandidate = null;
    var confirmed = true;
    final subscription = _subscription;
    _subscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      confirmed = false;
      _stopUnconfirmed = true;
    }
    try {
      await _recorder.stop();
    } catch (_) {
      confirmed = false;
      _stopUnconfirmed = true;
      if (mounted) {
        setState(() => _status = '마이크 중단을 확인하지 못했습니다. 앱을 종료하고 다시 실행하세요.');
      }
    }
    _detector.reset();
    _stopUnconfirmed = !confirmed;
    _stopping = false;
    if (mounted) {
      setState(
        () => _status = confirmed
            ? '마이크 시험을 중단했습니다.'
            : '마이크 중단을 확인하지 못했습니다. 앱을 종료하고 다시 실행하세요.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _candidateExpiry?.cancel();
    _subscription?.cancel();
    _recorder.dispose();
    _cloudClient?.close(force: true);
    unawaited(_player.stop().catchError((_) {}));
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusTitle = _sending
        ? '클라우드 처리 중'
        : _stopUnconfirmed
        ? '마이크 중단 확인 필요'
        : _starting || _stopping
        ? '마이크 준비 중'
        : _listening
        ? '기기에서 듣고 있습니다'
        : '마이크가 꺼져 있습니다';
    return MaterialApp(
      title: 'iPad 발화 감지 · 내부 시험',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF235C56)),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 600 ? 24 : 44,
                      vertical: constraints.maxWidth < 600 ? 32 : 56,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '가족 음성 도우미  /  팀 내부 시험',
                          style: TextStyle(
                            color: Color(0xFF547068),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'iPad 발화 감지 시험',
                          style: TextStyle(
                            color: const Color(0xFF192C2B),
                            fontSize: constraints.maxWidth < 600 ? 30 : 38,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '마이크 소리를 기기 안에서 확인하고 발화 후보만 셉니다.',
                          style: TextStyle(
                            color: Color(0xFF53615F),
                            fontSize: 18,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8F7),
                            border: Border.all(color: const Color(0xFFDCE5E1)),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: _listening
                                      ? const Color(0xFFD9EEE7)
                                      : const Color(0xFFE8EEEB),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  _listening
                                      ? Icons.mic_rounded
                                      : Icons.mic_off_rounded,
                                  color: const Color(0xFF235C56),
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                statusTitle,
                                style: const TextStyle(
                                  color: Color(0xFF192C2B),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _status,
                                  style: const TextStyle(
                                    color: Color(0xFF53615F),
                                    fontSize: 17,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              const Divider(color: Color(0xFFDCE5E1)),
                              const SizedBox(height: 12),
                              Text(
                                '감지한 발화 후보  $_candidateCount건',
                                style: const TextStyle(
                                  color: Color(0xFF235C56),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: FilledButton.icon(
                            onPressed:
                                _starting ||
                                    _stopping ||
                                    _sending ||
                                    _stopUnconfirmed
                                ? null
                                : (_listening ? _stop : _start),
                            icon: Icon(
                              _listening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                            ),
                            label: Text(
                              _starting || _stopping
                                  ? '마이크 준비 중'
                                  : (_listening ? '시험 중단' : '마이크 시험 시작'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        const Text(
                          '팀 내부 시험입니다. 기본적으로 발화 후보는 기기 안에서 즉시 폐기합니다. '
                          '자가 음성 후보 한 건만 아래에서 직접 클라우드 시험 API로 보낼 수 있습니다. '
                          '환자 구분과 실제 환자 자료 처리는 아직 하지 않습니다.',
                          style: TextStyle(
                            color: Color(0xFF63716F),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFDCE5E1)),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '클라우드 응답 · 자가 음성 시험',
                                style: TextStyle(
                                  color: Color(0xFF192C2B),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '서버와 음성 공급자에 오디오가 전송됩니다. 시험자 본인의 목소리만 사용하세요.',
                                style: TextStyle(
                                  color: Color(0xFF53615F),
                                  fontSize: 16,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 16),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('내 목소리로만 시험합니다'),
                                value: _ownVoiceTrial,
                                onChanged: _sending
                                    ? null
                                    : (value) {
                                        if (value != true) {
                                          _discardTrial();
                                        } else {
                                          setState(() => _ownVoiceTrial = true);
                                        }
                                      },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _endpoint,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: '내부 오디오 API 주소',
                                  hintText:
                                      'https://.../internal/synthetic/audio',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _token,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: '내부 시험 토큰',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed:
                                      _ownVoiceTrial &&
                                          _heldCandidate != null &&
                                          !_sending &&
                                          !_starting &&
                                          !_stopping &&
                                          _foreground
                                      ? _sendTrial
                                      : null,
                                  icon: const Icon(Icons.cloud_upload_rounded),
                                  label: Text(
                                    _sending ? '클라우드 처리 중' : '자가 음성 후보 한 건 보내기',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _cloudStatus,
                                  style: const TextStyle(
                                    color: Color(0xFF53615F),
                                    fontSize: 16,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              if (_cloudTranscript.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  '전사',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(_cloudTranscript),
                              ],
                              if (_cloudReply.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  '응답',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(_cloudReply),
                              ],
                              if (_playedReply) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: _stopReply,
                                  icon: const Icon(Icons.stop_rounded),
                                  label: const Text('음성 응답 중단'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
