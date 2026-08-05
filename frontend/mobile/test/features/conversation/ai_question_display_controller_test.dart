import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiQuestionDisplayController', () {
    test('새 messageId 질문은 자동 표시한다', () {
      final controller = AiQuestionDisplayController();

      final accepted = controller.receive(_question(101, '이 집에는 누가 있어?'));

      expect(accepted, isTrue);
      expect(controller.isVisible, isTrue);
      expect(controller.visibleQuestion?.messageId, 101);
    });

    test('이미 표시한 messageId는 다시 노출하지 않는다', () {
      final controller = AiQuestionDisplayController();
      controller.receive(_question(101, '이 집에는 누가 있어?'));
      controller.dismiss();

      final accepted = controller.receive(_question(101, '이 집에는 누가 있어?'));

      expect(accepted, isFalse);
      expect(controller.isVisible, isFalse);
      expect(controller.displayedMessageIds, {101});
    });

    test('질문 문구가 같아도 messageId가 다르면 새 질문으로 표시한다', () {
      final controller = AiQuestionDisplayController();
      controller.receive(_question(101, '이 집에는 누가 있어?'));
      controller.dismiss();

      final accepted = controller.receive(_question(102, '이 집에는 누가 있어?'));

      expect(accepted, isTrue);
      expect(controller.isVisible, isTrue);
      expect(controller.visibleQuestion?.messageId, 102);
      expect(controller.displayedMessageIds, {101, 102});
    });

    test('음성 답변이 무효가 된 질문은 다시 표시할 수 있다', () {
      // receive는 같은 messageId를 두 번 받지 않는다. 무음·거절로 답변이 무효가 되면
      // 새 질문을 만들지 않고 표시만 되살려 선택지로 답할 기회를 준다.
      final controller = AiQuestionDisplayController();
      controller.receive(_question(101, '이 집에는 누가 있어?'));
      controller.dismiss();

      controller.restore();

      expect(controller.isVisible, isTrue);
      expect(controller.visibleQuestion?.messageId, 101);
    });

    test('받은 질문이 없으면 복원하지 않는다', () {
      final controller = AiQuestionDisplayController();

      controller.restore();

      expect(controller.isVisible, isFalse);
      expect(controller.visibleQuestion, isNull);
    });

    test('이미 보이는 질문 복원은 알림을 만들지 않는다', () {
      final controller = AiQuestionDisplayController();
      controller.receive(_question(101, '이 집에는 누가 있어?'));
      var notificationCount = 0;
      controller.addListener(() => notificationCount++);

      controller.restore();

      expect(notificationCount, 0);
    });

    test('화면 상태 알림이 반복되어도 같은 질문 알림은 한 번만 발생한다', () {
      final controller = AiQuestionDisplayController();
      var notificationCount = 0;
      controller.addListener(() => notificationCount++);

      controller.receive(_question(101, '무슨 색으로 그렸어?'));
      controller.receive(_question(101, '무슨 색으로 그렸어?'));

      expect(notificationCount, 1);
    });
  });
}

AiQuestion _question(int messageId, String text) => AiQuestion(
  messageId: messageId,
  conversationId: 10,
  sequence: messageId - 100,
  text: text,
  options: const [],
  ttsAvailable: true,
  createdAt: DateTime(2026, 7, 23),
);
