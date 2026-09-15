import 'package:flutter/services.dart';

/// Sends only bounded PCM to the iPad's Korean on-device recognizer.
class OnDeviceSpeech {
  const OnDeviceSpeech();

  static const channel = MethodChannel('kof5/on_device_speech');

  Future<bool> available() async =>
      await channel.invokeMethod<bool>('available') ?? false;

  Future<bool> authorize() async =>
      await channel.invokeMethod<bool>('authorize') ?? false;

  Future<String?> transcribe(Uint8List pcm) async {
    if (pcm.isEmpty || pcm.length.isOdd || pcm.length > 16000 * 2 * 8) {
      throw const FormatException('8초 이하의 PCM16 발화 후보가 필요합니다.');
    }
    final text = await channel.invokeMethod<String>('transcribe', pcm);
    if (text != null && text.length > 500) {
      throw const FormatException('기기 내 전사 문장이 너무 깁니다.');
    }
    return text;
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}
