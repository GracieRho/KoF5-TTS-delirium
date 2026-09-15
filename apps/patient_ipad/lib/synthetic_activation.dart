/// Phase-0 self-voice script: a direct name opens a 60-second question window.
class SyntheticActivation {
  DateTime? _lastTurn;

  // ponytail: scripted name/question rule; replace only after measured ward activation and speaker evidence.
  bool accepts(String transcript, DateTime now) {
    final text = transcript.trim();
    if (text.isEmpty) return false;
    if (text.contains('수민아')) {
      _lastTurn = now;
      return true;
    }
    final active =
        _lastTurn != null &&
        now.difference(_lastTurn!) < const Duration(seconds: 60);
    if (active &&
        (text.contains('?') ||
            RegExp(r'며칠|몇 시|언제|어디|제주도|그만해').hasMatch(text))) {
      _lastTurn = text.contains('그만해') ? null : now;
      return true;
    }
    if (!active) _lastTurn = null;
    return false;
  }

  void reset() => _lastTurn = null;
}
