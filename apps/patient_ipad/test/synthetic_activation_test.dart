import 'package:flutter_test/flutter_test.dart';
import 'package:kof5_patient/synthetic_activation.dart';

void main() {
  test('scripted direct address opens only a short question window', () {
    final activation = SyntheticActivation();
    final now = DateTime.utc(2026, 9, 15, 6);
    expect(activation.accepts('TV 뉴스입니다', now), isFalse);
    expect(activation.accepts('오늘이 며칠이야', now), isFalse);
    expect(activation.accepts('수민아?', now), isTrue);
    expect(
      activation.accepts('TV 뉴스입니다', now.add(const Duration(seconds: 2))),
      isFalse,
    );
    expect(
      activation.accepts('오늘이 며칠이야', now.add(const Duration(seconds: 3))),
      isTrue,
    );
    expect(
      activation.accepts('그만해', now.add(const Duration(seconds: 4))),
      isTrue,
    );
    expect(
      activation.accepts('제주도 언제 갔었지', now.add(const Duration(seconds: 5))),
      isFalse,
    );
    expect(
      activation.accepts('수민아?', now.add(const Duration(seconds: 6))),
      isTrue,
    );
    expect(
      activation.accepts('제주도 언제 갔었지', now.add(const Duration(seconds: 67))),
      isFalse,
    );
  });
}
