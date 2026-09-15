/// Phase-0 self-voice script: a direct name opens a 60-second question window.
class SyntheticActivation {
  DateTime? _lastTurn;

  // ponytail: scripted name/question rule; replace only after measured ward activation and speaker evidence.
  bool accepts(String transcript, DateTime now) {
    final text = transcript.trim();
    if (text.isEmpty) return false;
    if (['이거 꺼', '말 걸지 마', '대화 그만', '그만해'].any(text.contains) ||
        text.replaceAll(RegExp(r'[.!?\s]+$'), '') == '싫어') {
      _lastTurn = null;
      return false;
    }
    if (text.contains('수민아')) {
      _lastTurn = now;
      return true;
    }
    final active =
        _lastTurn != null &&
        now.difference(_lastTurn!) < const Duration(seconds: 60);
    if (active &&
        (text.contains('?') || RegExp(r'며칠|몇 시|언제|어디|제주도').hasMatch(text))) {
      _lastTurn = now;
      return true;
    }
    if (!active) _lastTurn = null;
    return false;
  }

  void reset() => _lastTurn = null;
}
