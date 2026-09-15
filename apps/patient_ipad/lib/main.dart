import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'on_device_speech.dart';
import 'speech_candidate.dart';
import 'synthetic_activation.dart';
import 'synthetic_cloud_trial.dart';
import 'trial_audio_player.dart';

void main() => runApp(const PatientMicDemo());

class PatientMicDemo extends StatefulWidget {
  const PatientMicDemo({
    super.key,
    this.cloudTrial = sendOwnVoiceCandidate,
    this.textTrial = sendOwnVoiceText,
  });

  final Future<SyntheticCloudReply> Function(HttpClient, Uri, String, Uint8List)
  cloudTrial;
  final Future<SyntheticCloudReply> Function(
    HttpClient,
    Uri,
    String,
    String,
    String,
  )
  textTrial;

  @override
  State<PatientMicDemo> createState() => _PatientMicDemoState();
}

class _PatientMicDemoState extends State<PatientMicDemo>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _detector = SpeechCandidateDetector();
  final _player = TrialAudioPlayer();
  final _speech = const OnDeviceSpeech();
  final _activation = SyntheticActivation();
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
  int? _playbackOwnerGeneration;
  Future<bool>? _replyStop;
  var _cloudStatus = '자가 음성 시험을 확인하면 발화 후보 한 건을 직접 보낼 수 있습니다.';
  var _cloudTranscript = '';
  var _cloudReply = '';
  var _localEnabled = false;
  var _recognizing = false;
  var _speechStopUnconfirmed = false;
  Future<bool>? _speechStop;
  var _localGeneration = 0;
  var _localStatus = '한국어 기기 내 인식 지원 여부를 확인하지 않았습니다.';
  var _localTranscript = '';
  var _autoTextTrial = false;

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
    _localGeneration++;
    final cancellingSpeech =
        _recognizing ||
        _localEnabled ||
        _speechStop != null ||
        _speechStopUnconfirmed;
    _localEnabled = false;
    _autoTextTrial = false;
    _activation.reset();
    if (cancellingSpeech) unawaited(_cancelLocalSpeech());
    _cloudClient?.close(force: true);
    _cloudClient = null;
    _token.clear();
    _candidateExpiry?.cancel();
    _candidateExpiry = null;
    _heldCandidate = null;
    _ownVoiceTrial = false;
    _sending = false;
    final stoppingPlayback = _playedReply;
    if (mounted) {
      setState(() {
        _cloudStatus = stoppingPlayback
            ? '시험 자료 폐기 · 음성 재생 중단 확인 중'
            : '시험 자료를 폐기했습니다.';
        _cloudTranscript = '';
        _cloudReply = '';
        _localTranscript = '';
        _localStatus = cancellingSpeech
            ? '기기 내 전사 중단 확인 중 · 후보를 화면에서 숨겼습니다.'
            : '기기 내 전사 후보를 폐기했습니다.';
      });
    }
    if (stoppingPlayback) {
      unawaited(_stopReply(successStatus: '시험 자료를 폐기했습니다.').then((_) {}));
    }
  }

  Future<bool> _cancelLocalSpeech() {
    final pending = _speechStop;
    if (pending != null) return pending;
    final future = _performCancelLocalSpeech();
    _speechStop = future;
    future.whenComplete(() {
      if (identical(_speechStop, future)) _speechStop = null;
    });
    return future;
  }

  Future<bool> _performCancelLocalSpeech() async {
    try {
      await _speech.cancel().timeout(const Duration(seconds: 5));
      _recognizing = false;
      _speechStopUnconfirmed = false;
      if (mounted && !_ownVoiceTrial) {
        setState(() => _localStatus = '기기 내 전사 중단을 확인하고 후보를 폐기했습니다.');
      }
      return true;
    } catch (_) {
      _speechStopUnconfirmed = true;
      _localEnabled = false;
      if (mounted) {
        setState(
          () => _localStatus = '기기 내 전사 중단을 확인하지 못했습니다. 다시 확인하기 전 새 전사를 차단합니다.',
        );
      }
      return false;
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

  Future<bool> _stopReply({String successStatus = '음성 응답 재생을 중단했습니다.'}) {
    final pending = _replyStop;
    if (pending != null) return pending;
    final future = _performStopReply(successStatus);
    _replyStop = future;
    future.whenComplete(() {
      if (identical(_replyStop, future)) _replyStop = null;
    });
    return future;
  }

  Future<bool> _performStopReply(String successStatus) async {
    try {
      await _player.stop().timeout(const Duration(seconds: 5));
      _playedReply = false;
      if (mounted) {
        setState(() {
          _cloudStatus = successStatus;
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _cloudStatus = '음성 응답 중단을 확인하지 못했습니다. 다시 중단하세요.');
      }
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
      _status = _autoTextTrial
          ? '발화 후보 $_candidateCount건 감지 · 오디오는 자동 전송하지 않습니다.'
          : '발화 후보 $_candidateCount건 감지 · 자동 전송 없음';
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
    if (_localEnabled &&
        !_recognizing &&
        !_speechStopUnconfirmed &&
        _speechStop == null &&
        _ownVoiceTrial) {
      unawaited(_recognizeCandidate(candidate));
    }
  }

  Future<void> _enableLocalSpeech() async {
    final generation = ++_localGeneration;
    try {
      if (_speechStop != null || _speechStopUnconfirmed) {
        setState(() => _localStatus = '이전 기기 내 전사 중단을 다시 확인하고 있습니다.');
        if (!await _cancelLocalSpeech()) {
          return;
        }
        if (!mounted ||
            !_foreground ||
            !_ownVoiceTrial ||
            generation != _localGeneration) {
          return;
        }
      }
      final available = await _speech.available();
      if (!mounted ||
          !_foreground ||
          !_ownVoiceTrial ||
          generation != _localGeneration) {
        return;
      }
      if (!available) {
        setState(
          () => _localStatus = '이 iPad는 한국어 기기 내 전사를 지원하지 않아 후보를 전사하지 않습니다.',
        );
        return;
      }
      final authorized = await _speech.authorize();
      if (!mounted ||
          !_foreground ||
          !_ownVoiceTrial ||
          generation != _localGeneration) {
        return;
      }
      setState(() {
        _localEnabled = authorized;
        _localStatus = authorized
            ? '한국어 기기 내 전사 준비됨 · 후보 오디오는 서버에 보내지 않습니다.'
            : '음성 인식 권한이 없어 기기 내 전사를 사용하지 않습니다.';
      });
    } catch (_) {
      if (mounted && generation == _localGeneration) {
        setState(() => _localStatus = '기기 내 전사를 준비하지 못해 후보를 전사하지 않습니다.');
      }
    }
  }

  Future<void> _recognizeCandidate(Uint8List candidate) async {
    final generation = ++_localGeneration;
    _recognizing = true;
    setState(() => _localStatus = '자가 음성 후보를 iPad 안에서 전사하고 있습니다.');
    String? directedText;
    try {
      final transcript = await _speech
          .transcribe(candidate)
          .timeout(const Duration(seconds: 12));
      if (!mounted ||
          !_foreground ||
          !_ownVoiceTrial ||
          generation != _localGeneration) {
        return;
      }
      setState(() {
        _localTranscript = transcript ?? '';
        _localStatus = _localTranscript.isEmpty
            ? '기기 내에서 말을 확인하지 못했습니다. 후보 오디오는 자동 전송하지 않습니다.'
            : _autoTextTrial
            ? 'iPad 기기 내 전사 완료 · 환자 역할에게 향한 글만 판정합니다.'
            : 'iPad 기기 내 전사 완료 · 글과 오디오 모두 자동 전송하지 않습니다.';
      });
      if (_autoTextTrial &&
          _localTranscript.isNotEmpty &&
          _activation.accepts(_localTranscript, DateTime.now())) {
        directedText = _localTranscript;
      }
    } catch (_) {
      if (mounted && generation == _localGeneration) {
        setState(() => _localStatus = '기기 내 전사에 실패했습니다. 후보 오디오는 자동 전송하지 않습니다.');
      }
    } finally {
      if (generation == _localGeneration) _recognizing = false;
    }
    if (directedText != null &&
        mounted &&
        _foreground &&
        generation == _localGeneration &&
        _autoTextTrial) {
      unawaited(_sendTextTrial(directedText));
    }
  }

  Future<void> _sendTrial() async {
    if (!_ownVoiceTrial ||
        _heldCandidate == null ||
        _autoTextTrial ||
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
    if (!await _stopForTrial(generation)) return;
    await _runTrialRequest(generation, (client) {
      final endpoint = Uri.parse(_endpoint.text.trim());
      return widget.cloudTrial(client, endpoint, _token.text, pcm);
    }, textOnly: false);
  }

  Future<void> _sendTextTrial(String transcript) async {
    if (!_autoTextTrial ||
        !_ownVoiceTrial ||
        _sending ||
        _speechStopUnconfirmed ||
        _speechStop != null ||
        !_foreground) {
      return;
    }
    final generation = ++_trialGeneration;
    _candidateExpiry?.cancel();
    _candidateExpiry = null;
    _heldCandidate = null;
    setState(() {
      _sending = true;
      _cloudStatus = 'iPad 판정 후 글만 보내기 위해 마이크를 중단하고 있습니다.';
      _cloudTranscript = '';
      _cloudReply = '';
    });
    if (!await _stopForTrial(generation)) return;
    await _runTrialRequest(generation, (client) {
      final endpoint = Uri.parse(
        _endpoint.text.trim(),
      ).replace(path: '/internal/synthetic/text');
      return widget.textTrial(
        client,
        endpoint,
        _token.text,
        transcript,
        'DIRECTED',
      );
    }, textOnly: true);
  }

  Future<bool> _stopForTrial(int generation) async {
    await _stop();
    if (!mounted ||
        !_foreground ||
        !_ownVoiceTrial ||
        generation != _trialGeneration) {
      return false;
    }
    if (_stopUnconfirmed ||
        _speechStopUnconfirmed ||
        _speechStop != null ||
        _recognizing ||
        _stopping ||
        _listening) {
      setState(() {
        _sending = false;
        _cloudStatus = '마이크 또는 기기 내 전사 중단을 확인하지 못해 전송하지 않았습니다.';
      });
      return false;
    }
    return true;
  }

  Future<void> _runTrialRequest(
    int generation,
    Future<SyntheticCloudReply> Function(HttpClient) send, {
    required bool textOnly,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _cloudClient = client;
    try {
      final result = await send(client).timeout(const Duration(seconds: 70));
      if (!mounted || !_foreground || generation != _trialGeneration) return;
      setState(() {
        _cloudTranscript = result.transcript;
        _cloudReply = result.reply ?? '';
        _cloudStatus = result.mp3 == null
            ? '서버 안전 경로에서 음성 응답을 만들지 않았습니다.'
            : textOnly
            ? '글 전용 클라우드 시험 응답 · 재생 시작'
            : '클라우드 자가 음성 시험 응답 · 재생 시작';
      });
      if (result.mp3 != null) {
        _playbackOwnerGeneration = generation;
        setState(() => _playedReply = true);
        await _player.play(result.mp3!).timeout(const Duration(seconds: 10));
        if ((!mounted || !_foreground || generation != _trialGeneration) &&
            _playbackOwnerGeneration == generation) {
          await _stopReply(successStatus: '시험 자료를 폐기했습니다.');
        }
      }
    } catch (_) {
      if (textOnly) _activation.reset();
      if (_playbackOwnerGeneration == generation && _playedReply) {
        final stopped = await _stopReply();
        if (!stopped) return;
      }
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
    _localGeneration++;
    final speechStopped =
        _recognizing ||
            _localEnabled ||
            _speechStop != null ||
            _speechStopUnconfirmed
        ? _cancelLocalSpeech()
        : Future<bool>.value(true);
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
    await speechStopped;
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
    _trialGeneration++;
    _localGeneration++;
    if (_recognizing ||
        _localEnabled ||
        _speechStop != null ||
        _speechStopUnconfirmed) {
      unawaited(_cancelLocalSpeech());
    }
    _candidateExpiry?.cancel();
    _subscription?.cancel();
    _recorder.dispose();
    _cloudClient?.close(force: true);
    if (_playedReply) unawaited(_stopReply().then((_) {}));
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
                                          unawaited(_enableLocalSpeech());
                                        }
                                      },
                              ),
                              const SizedBox(height: 8),
                              Semantics(
                                liveRegion: true,
                                child: Text(_localStatus),
                              ),
                              if (_ownVoiceTrial &&
                                  _localTranscript.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('기기 내 전사: $_localTranscript'),
                              ],
                              if (_speechStopUnconfirmed && _ownVoiceTrial)
                                TextButton(
                                  onPressed: _speechStop == null
                                      ? () => unawaited(_enableLocalSpeech())
                                      : null,
                                  child: const Text('전사 중단 다시 확인'),
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
                              const SizedBox(height: 12),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('내 기기 내 전사 글만 자동 내부 시험'),
                                subtitle: const Text(
                                  '내 목소리에서 이름을 부른 뒤 짧은 질문만 같은 서버의 글 API로 보냅니다. '
                                  '글은 hosted LLM에 전달될 수 있고 후보 오디오는 자동으로 보내지 않습니다.',
                                ),
                                value: _autoTextTrial,
                                onChanged: (value) {
                                  if (value != true) {
                                    _discardTrial();
                                    return;
                                  }
                                  if (!_ownVoiceTrial ||
                                      !_localEnabled ||
                                      _sending ||
                                      _speechStopUnconfirmed ||
                                      _speechStop != null) {
                                    return;
                                  }
                                  final endpoint = Uri.tryParse(
                                    _endpoint.text.trim(),
                                  );
                                  if (endpoint?.path !=
                                          '/internal/synthetic/audio' ||
                                      _token.text.length < 32) {
                                    setState(
                                      () => _cloudStatus =
                                          '내부 오디오 API 주소와 토큰을 먼저 확인하세요.',
                                    );
                                    return;
                                  }
                                  _activation.reset();
                                  setState(() {
                                    _autoTextTrial = true;
                                    _cloudStatus =
                                        '자가 음성의 기기 내 판정된 글만 내부 API로 자동 시험합니다.';
                                  });
                                },
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed:
                                      _ownVoiceTrial &&
                                          _heldCandidate != null &&
                                          !_autoTextTrial &&
                                          !_sending &&
                                          !_starting &&
                                          !_stopping &&
                                          !_speechStopUnconfirmed &&
                                          _speechStop == null &&
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
                                  onPressed: _sending
                                      ? null
                                      : () {
                                          unawaited(_stopReply().then((_) {}));
                                        },
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
