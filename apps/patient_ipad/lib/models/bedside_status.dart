enum BedsideStatus { listening, playing, resting }

extension BedsideStatusCopy on BedsideStatus {
  String get title => switch (this) {
    BedsideStatus.listening => '안내를 듣고 있어요',
    BedsideStatus.playing => '안내 말씀을 들려드리고 있어요',
    BedsideStatus.resting => '편안히 쉬세요',
  };

  String get description => switch (this) {
    BedsideStatus.listening => '말씀하시면 조용히 듣겠습니다.',
    BedsideStatus.playing => '잠시만 편안하게 들어주세요.',
    BedsideStatus.resting => '필요할 때 병실 호출 버튼을 이용해주세요.',
  };
}
