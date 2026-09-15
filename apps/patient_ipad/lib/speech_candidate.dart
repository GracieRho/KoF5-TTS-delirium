import 'dart:typed_data';

/// Local energy-based speech *candidate* detector; it cannot identify a patient.
class SpeechCandidateDetector {
  SpeechCandidateDetector({
    this.sampleRate = 16000,
    this.energyThreshold = 0.035,
  });

  final int sampleRate;
  // ponytail: fixed energy threshold is a demo ceiling; calibrate against hospital noise before patient use.
  final double energyThreshold;
  final List<Uint8List> _preroll = [];
  final List<Uint8List> _candidate = [];
  int _prerollBytes = 0;
  int _speechSamples = 0;
  int _quietSamples = 0;
  int _candidateBytes = 0;

  Uint8List? add(Uint8List pcm) {
    if (pcm.isEmpty || pcm.length.isOdd) return null;
    if (pcm.length > sampleRate * 2) {
      reset(); // Reject an oversized callback rather than retaining unbounded audio.
      return null;
    }
    final samples = pcm.length ~/ 2;
    final view = ByteData.sublistView(pcm);
    var energy = 0.0;
    for (var i = 0; i < samples; i++) {
      energy += view.getInt16(i * 2, Endian.little).abs() / 32768;
    }
    final speech = energy / samples >= energyThreshold;

    if (_candidate.isEmpty) {
      _preroll.add(pcm);
      _prerollBytes += pcm.length;
      while (_prerollBytes > sampleRate * 2 && _preroll.length > 1) {
        _prerollBytes -= _preroll.removeAt(0).length;
      }
      _speechSamples = speech ? _speechSamples + samples : 0;
      if (_speechSamples < sampleRate ~/ 5) return null;
      _candidate.addAll(_preroll);
      _candidateBytes = _prerollBytes;
      _preroll.clear();
      _prerollBytes = 0;
      _quietSamples = 0;
      return null;
    }

    final remaining = sampleRate * 2 * 8 - _candidateBytes;
    final kept = pcm.length <= remaining
        ? pcm
        : Uint8List.sublistView(pcm, 0, remaining);
    _candidate.add(kept);
    _candidateBytes += kept.length;
    _quietSamples = speech ? 0 : _quietSamples + samples;
    if (_quietSamples < sampleRate * 3 ~/ 5 &&
        _candidateBytes < sampleRate * 2 * 8) {
      return null;
    }
    final result = Uint8List(_candidateBytes);
    var offset = 0;
    for (final chunk in _candidate) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    reset();
    return result;
  }

  void reset() {
    _preroll.clear();
    _candidate.clear();
    _prerollBytes = 0;
    _speechSamples = 0;
    _quietSamples = 0;
    _candidateBytes = 0;
  }
}
