import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiQuestionSelectionController', () {
    test('질문의 유효한 선택지를 선택한다', () {
      final controller = AiQuestionSelectionController();
      addTearDown(controller.dispose);
      controller.beginQuestion(_question(10));

      final selected = controller.select(_question(10), 2);

      expect(selected, isTrue);
      expect(controller.questionMessageId, 10);
      expect(controller.selectedOptionId, 2);
    });

    test('질문에 없는 optionId는 선택하지 않는다', () {
      final controller = AiQuestionSelectionController();
      addTearDown(controller.dispose);
      controller.beginQuestion(_question(10));

      final selected = controller.select(_question(10), 99);

      expect(selected, isFalse);
      expect(controller.selectedOptionId, isNull);
    });

    test('새 질문이 도착하면 이전 선택 상태를 초기화한다', () {
      final controller = AiQuestionSelectionController();
      addTearDown(controller.dispose);
      controller.beginQuestion(_question(10));
      controller.select(_question(10), 1);

      controller.beginQuestion(_question(11));

      expect(controller.questionMessageId, 11);
      expect(controller.selectedOptionId, isNull);
    });

    test('질문 직후에는 숨기고 설정된 시간이 지난 뒤 선택지를 표시한다', () async {
      final controller = AiQuestionSelectionController(
        revealDelay: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      controller.beginQuestion(_question(10));
      expect(controller.optionsVisible, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.optionsVisible, isTrue);
    });

    test('기본 선택지 노출 대기 시간은 2.5초다', () {
      final controller = AiQuestionSelectionController();
      addTearDown(controller.dispose);

      expect(controller.revealDelay, const Duration(milliseconds: 2500));
    });
  });
}

AiQuestion _question(int messageId) => AiQuestion(
  messageId: messageId,
  conversationId: 20,
  sequence: 1,
  text: '그림에는 누가 함께 있어?',
  options: const [
    AiQuestionOption(
      optionId: 1,
      type: 'TEXT',
      label: '가족이 있어',
      value: '가족이 있어',
    ),
    AiQuestionOption(
      optionId: 2,
      type: 'TEXT',
      label: '친구가 있어',
      value: '친구가 있어',
    ),
  ],
  ttsAvailable: true,
  createdAt: DateTime(2026, 7, 23),
);
