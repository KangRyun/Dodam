import 'package:dodam/features/notification/domain/entities/push_message.dart';
import 'package:dodam/features/notification/domain/services/push_dedupe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PushMessage message(int id) => PushMessage(
    notificationId: id,
    type: 'ANALYSIS_COMPLETED',
    title: '분석이 완료됐어요',
    content: '리포트를 확인해 보세요',
  );

  test('같은 알림은 한 번만 표시한다', () {
    final dedupe = PushDedupe();

    expect(dedupe.shouldShow(message(900)), isTrue);
    expect(dedupe.shouldShow(message(900)), isFalse);
  });

  test('다른 알림은 각각 표시한다', () {
    final dedupe = PushDedupe();

    expect(dedupe.shouldShow(message(900)), isTrue);
    expect(dedupe.shouldShow(message(901)), isTrue);
  });

  test('보관 한도를 넘으면 가장 오래된 기록부터 밀어낸다', () {
    final dedupe = PushDedupe(capacity: 2);

    dedupe.shouldShow(message(1));
    dedupe.shouldShow(message(2));
    dedupe.shouldShow(message(3));

    // 1은 밀려났으므로 다시 표시 대상이 된다.
    expect(dedupe.shouldShow(message(1)), isTrue);
    // 3은 아직 기억하고 있다.
    expect(dedupe.shouldShow(message(3)), isFalse);
  });

  test('clear 후에는 다시 표시한다', () {
    final dedupe = PushDedupe();
    dedupe.shouldShow(message(900));

    dedupe.clear();

    expect(dedupe.shouldShow(message(900)), isTrue);
  });
}
