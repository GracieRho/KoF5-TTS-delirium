import 'dart:typed_data';

class RuntimeHospitalMessage {
  const RuntimeHospitalMessage({
    required this.id,
    required this.text,
    required this.audio,
  });

  final String id;
  final String text;
  final Uint8List audio;
}
