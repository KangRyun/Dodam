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

    test('화면 상태 알림이 반복되어도 같은 질문 알림은 한 번만 발생한다', () {
      final controller = AiQuestionDisplayController();
      var notificationCount = 0;
      controller.addListener(() => notificationCount++);

      controller.receive(_question(101, '무슨 색으로 그렸어?'));
      controller.receive(_question(101, '무슨 색으로 그렸어?'));

      expect(notificationCount, 1);
    });

    test(
      'an unresolved question remains until its matching message resolves',
      () {
        final controller = AiQuestionDisplayController();
        controller.receive(_question(101, 'first question'));

        expect(controller.hasUnresolvedQuestion, isTrue);
        expect(controller.resolveQuestion(100), isFalse);
        expect(controller.visibleQuestion?.messageId, 101);
        expect(controller.hasUnresolvedQuestion, isTrue);

        expect(controller.resolveQuestion(101), isTrue);
        expect(controller.hasUnresolvedQuestion, isFalse);
        expect(controller.visibleQuestion, isNull);
        expect(controller.resolveQuestion(101), isFalse);
      },
    );

    test('resolving an older message cannot dismiss a newer question', () {
      final controller = AiQuestionDisplayController();
      controller.receive(_question(101, 'first question'));
      controller.receive(_question(102, 'newer question'));

      expect(controller.resolveQuestion(101), isFalse);
      expect(controller.visibleQuestion?.messageId, 102);
      expect(controller.isVisible, isTrue);
    });

    test('clearConversation rejects late questions terminally', () {
      final controller = AiQuestionDisplayController();
      controller.receive(_question(101, 'first question'));

      controller.clearConversation();
      final accepted = controller.receive(_question(102, 'late question'));

      expect(accepted, isFalse);
      expect(controller.hasUnresolvedQuestion, isFalse);
      expect(controller.visibleQuestion, isNull);
      expect(controller.isVisible, isFalse);
    });

    test('a duplicate message cannot trigger a second presentation', () {
      final controller = AiQuestionDisplayController();
      var presentationCount = 0;
      controller.addListener(() => presentationCount += 1);

      expect(controller.receive(_question(101, 'first question')), isTrue);
      expect(controller.receive(_question(101, 'duplicate question')), isFalse);

      expect(presentationCount, 1);
      expect(controller.visibleQuestion?.text, 'first question');
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
