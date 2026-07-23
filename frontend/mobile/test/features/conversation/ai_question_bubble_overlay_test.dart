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
              AiQuestionBubbleOverlay(question: _question, visible: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dodami-character')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-bubble')), findsOneWidget);
    expect(find.text('그림에는 누가 함께 있어?'), findsOneWidget);
  });

  testWidgets('질문 데이터가 없으면 캐릭터와 말풍선을 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [AiQuestionBubbleOverlay(question: null, visible: false)],
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
  options: const [],
  ttsAvailable: true,
  createdAt: DateTime(2026, 7, 23),
);
