enum BedsideStatus { waiting, playing, resting }

extension BedsideStatusCopy on BedsideStatus {
  String get title => switch (this) {
    BedsideStatus.waiting => '병원 안내를 기다리고 있어요',
    BedsideStatus.playing => '안내 말씀을 들려드리고 있어요',
    BedsideStatus.resting => '편안히 쉬세요',
  };

  String get description => switch (this) {
    BedsideStatus.waiting => '승인된 안내가 도착하면 바로 알려드릴게요.',
    BedsideStatus.playing => '잠시만 편안하게 들어주세요.',
    BedsideStatus.resting => '필요할 때 병실 호출 버튼을 이용해주세요.',
  };
}
