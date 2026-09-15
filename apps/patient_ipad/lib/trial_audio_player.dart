import 'package:flutter/services.dart';

class TrialAudioPlayer {
  static const _channel = MethodChannel('kof5/trial_audio');

  Future<void> play(Uint8List mp3, {bool concurrentMic = false}) =>
      _channel.invokeMethod<void>(
        'play',
        concurrentMic ? {'audio': mp3, 'concurrentMic': true} : mp3,
      );

  Future<bool> waitFinished() async =>
      await _channel.invokeMethod<bool>('waitFinished') == true;

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
