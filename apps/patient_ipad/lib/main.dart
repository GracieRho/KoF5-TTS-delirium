import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'speech_candidate.dart';

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
  StreamSubscription<Uint8List>? _subscription;
  var _listening = false;
  var _starting = false;
  var _stopping = false;
  var _foreground = true;
  var _stopUnconfirmed = false;
  var _candidateCount = 0;
  var _status = '마이크 시험을 시작할 수 있습니다.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) _stop();
  }

  Future<void> _start() async {
    if (_starting ||
        _stopping ||
        _listening ||
        _stopUnconfirmed ||
        !_foreground) {
      return;
    }
    setState(() => _starting = true);
    try {
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

  void _onAudio(Uint8List pcm) {
    if (!mounted || !_foreground || !_listening) return;
    final candidate = _detector.add(pcm);
    if (candidate == null || !mounted) return;
    // The prototype counts a candidate, then discards its PCM. No audio leaves the iPad.
    setState(() {
      _candidateCount++;
      _status = '발화 후보 $_candidateCount건 감지 · 서버 전송 없음';
    });
  }

  Future<void> _stop() async {
    if (_stopping || (!_listening && _subscription == null)) return;
    _stopping = true;
    _listening = false;
    _detector.reset();
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
    _subscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusTitle = _stopUnconfirmed
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
                                _starting || _stopping || _stopUnconfirmed
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
                          '팀 내부 시험입니다. 발화 후보는 기기 안에서 즉시 폐기합니다. '
                          '환자 구분·녹음 보관·클라우드 전송은 아직 하지 않습니다.',
                          style: TextStyle(
                            color: Color(0xFF63716F),
                            fontSize: 15,
                            height: 1.5,
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
