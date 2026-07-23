import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('질문이 도착하면 도다미와 질문 말풍선을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: _question,
                visible: true,
                selectedOptionId: null,
                onOptionSelected: (_) {},
                showResponseActions: true,
                submissionStatus: OptionAnswerSubmissionStatus.idle,
                skipStatus: QuestionSkipStatus.idle,
                endStatus: ConversationEndStatus.idle,
                onEnd: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dodami-character')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-bubble')), findsOneWidget);
    expect(find.text('그림에는 누가 함께 있어?'), findsOneWidget);
    expect(find.text('가족이 있어'), findsOneWidget);
    expect(find.text('친구가 있어'), findsOneWidget);
    expect(find.text('이 질문은 넘어갈래'), findsOneWidget);
    expect(find.text('이제 질문 그만 받을래'), findsOneWidget);
  });

  testWidgets('선택지를 누르면 optionId를 전달하고 선택 상태를 표시한다', (tester) async {
    int? selectedOptionId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: _question,
                visible: true,
                selectedOptionId: 1,
                onOptionSelected: (optionId) => selectedOptionId = optionId,
                showResponseActions: true,
                submissionStatus: OptionAnswerSubmissionStatus.idle,
                skipStatus: QuestionSkipStatus.idle,
                endStatus: ConversationEndStatus.idle,
                onEnd: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-question-option-2')));
    expect(selectedOptionId, 2);
  });

  testWidgets('말 안 할래를 누르면 건너뛰기 요청을 전달한다', (tester) async {
    var skipRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: _question,
                visible: true,
                selectedOptionId: null,
                onOptionSelected: (_) {},
                showResponseActions: true,
                submissionStatus: OptionAnswerSubmissionStatus.idle,
                skipStatus: QuestionSkipStatus.idle,
                endStatus: ConversationEndStatus.idle,
                onEnd: () {},
                onSkip: () => skipRequested = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-question-skip')));
    expect(skipRequested, isTrue);
  });

  testWidgets('대화 그만하기를 누르면 종료 확인 요청을 전달한다', (tester) async {
    var endRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: _question,
                visible: true,
                selectedOptionId: null,
                onOptionSelected: (_) {},
                showResponseActions: true,
                submissionStatus: OptionAnswerSubmissionStatus.idle,
                skipStatus: QuestionSkipStatus.idle,
                onSkip: () {},
                endStatus: ConversationEndStatus.idle,
                onEnd: () => endRequested = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-conversation-end')));
    expect(endRequested, isTrue);
  });

  testWidgets('질문 데이터가 없으면 캐릭터와 말풍선을 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: null,
                visible: false,
                selectedOptionId: null,
                onOptionSelected: (_) {},
                showResponseActions: false,
                submissionStatus: OptionAnswerSubmissionStatus.idle,
                skipStatus: QuestionSkipStatus.idle,
                endStatus: ConversationEndStatus.idle,
                onEnd: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('dodami-character')), findsNothing);
    expect(find.byKey(const ValueKey('ai-question-bubble')), findsNothing);
  });
}

final _question = AiQuestion(
  messageId: 10,
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
