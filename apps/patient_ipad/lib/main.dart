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
        await _recorder.stop();
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
    var confirmed = true;
    try {
      await _recorder.stop();
    } catch (_) {
      confirmed = false;
    }
    try {
      await _subscription?.cancel();
    } catch (_) {
      confirmed = false;
    }
    _subscription = null;
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
  Widget build(BuildContext context) => MaterialApp(
    title: '가족 음성 대화 · 마이크 시험',
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq, size: 72),
                const SizedBox(height: 24),
                const Text('iPad 마이크 내부 시험', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 16),
                Text(_status, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _starting || _stopping || _stopUnconfirmed
                      ? null
                      : (_listening ? _stop : _start),
                  child: Text(
                    _starting || _stopping
                        ? '마이크 준비 중'
                        : (_listening ? '시험 중단' : '마이크 시험 시작'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '시험용 화면입니다. 발화 후보는 기기 안에서 즉시 폐기하며 '
                  '환자 구분·녹음 보관·클라우드 전송은 하지 않습니다.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
