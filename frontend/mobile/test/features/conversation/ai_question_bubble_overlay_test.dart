import 'dart:ui' show SemanticsAction;

import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('질문이 도착하면 도다미와 질문 말풍선을 표시한다', (tester) async {
    final semantics = tester.ensureSemantics();
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
    expect(find.text('이 질문 건너뛰기'), findsOneWidget);
    expect(find.text('질문 그만 받기'), findsOneWidget);
    expect(find.bySemanticsLabel('현재 질문 건너뛰기'), findsOneWidget);
    expect(find.bySemanticsLabel('AI 질문 그만 받기'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('현재 질문 건너뛰기'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('AI 질문 그만 받기'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    final skipIllustration = tester.widget<Image>(
      find.byKey(const ValueKey('ai-question-skip-illustration')),
    );
    final stopIllustration = tester.widget<Image>(
      find.byKey(const ValueKey('ai-question-stop-illustration')),
    );
    expect(
      (skipIllustration.image as AssetImage).assetName,
      'assets/images/conversation/question_skip_pastel.png',
    );
    expect(
      (stopIllustration.image as AssetImage).assetName,
      'assets/images/conversation/question_stop_pastel.png',
    );
    expect(skipIllustration.width, 30);
    expect(stopIllustration.width, 30);
    expect(skipIllustration.excludeFromSemantics, isTrue);
    expect(stopIllustration.excludeFromSemantics, isTrue);
    semantics.dispose();
  });

  testWidgets('선택지를 누르면 optionId를 전달하고 선택 상태를 표시한다', (tester) async {
    String? selectedOptionId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: _question,
                visible: true,
                selectedOptionId: '1',
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
    expect(selectedOptionId, '2');
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

  testWidgets('재시도 불가 Voice 실패에서는 녹음 UI를 직접 차단한다', (tester) async {
    final controller = VoiceRecordingController(_FakeVoiceRecorder());
    addTearDown(controller.dispose);
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
                voiceRecordingController: controller,
                voiceAnswerUploadStatus: VoiceAnswerUploadStatus.failure,
                voiceRetryable: false,
              ),
            ],
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('voice-recording-toggle')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('voice-answer-upload-retry')),
      findsNothing,
    );
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

  testWidgets('모바일 가로의 긴 질문·선택지·녹음 상태는 내부 스크롤로 조작할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(844, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = VoiceRecordingController(_FakeVoiceRecorder());
    addTearDown(controller.dispose);
    await controller.start();
    var endRequestCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              AiQuestionBubbleOverlay(
                question: _longQuestion,
                visible: true,
                selectedOptionId: null,
                onOptionSelected: (_) {},
                showResponseActions: true,
                submissionStatus: OptionAnswerSubmissionStatus.idle,
                skipStatus: QuestionSkipStatus.idle,
                endStatus: ConversationEndStatus.idle,
                onEnd: () => endRequestCount += 1,
                onSkip: () {},
                voiceRecordingController: controller,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('ai-question-overlay-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-recording-toggle')),
      findsOneWidget,
    );

    final overlayScroll = find.byKey(
      const ValueKey('ai-question-overlay-scroll'),
    );
    final endButton = find.byKey(const ValueKey('ai-conversation-end'));
    final viewportBeforeScroll = tester.getRect(overlayScroll);
    final endBeforeScroll = tester.getRect(endButton);
    expect(
      endBeforeScroll.top,
      greaterThanOrEqualTo(viewportBeforeScroll.bottom),
    );

    await tester.ensureVisible(endButton);
    await tester.pumpAndSettle();

    final viewportAfterScroll = tester.getRect(overlayScroll);
    final endAfterScroll = tester.getRect(endButton);
    expect(endAfterScroll.top, greaterThanOrEqualTo(viewportAfterScroll.top));
    expect(
      endAfterScroll.bottom,
      lessThanOrEqualTo(viewportAfterScroll.bottom),
    );
    expect(tester.takeException(), isNull);
    final endSize = tester.getSize(endButton);
    expect(endSize.width, greaterThanOrEqualTo(48));
    expect(endSize.height, greaterThanOrEqualTo(48));
    await tester.tap(endButton);
    await tester.pump();
    expect(endRequestCount, 1);
    expect(tester.takeException(), isNull);

    await controller.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('액션 카드는 좁은 폭·태블릿 가로·글자 2배에서 겹치지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final testCase in <({Size size, bool compact})>[
      (size: const Size(390, 844), compact: true),
      (size: const Size(1280, 800), compact: false),
    ]) {
      tester.view.physicalSize = testCase.size;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
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
                  compact: testCase.compact,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final skip = find.byKey(const ValueKey('ai-question-skip'));
      final stop = find.byKey(const ValueKey('ai-conversation-end'));
      await tester.ensureVisible(stop);
      await tester.pumpAndSettle();

      expect(tester.getSize(skip).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(stop).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(skip).bottom, lessThan(tester.getRect(stop).top));
      expect(
        tester
            .widget<Image>(
              find.byKey(const ValueKey('ai-question-skip-illustration')),
            )
            .width,
        testCase.compact ? 26 : 30,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Overlay 바깥 Canvas 입력은 전달하고 내부 버튼 입력은 차단한다', (tester) async {
    tester.view.physicalSize = const Size(844, 419);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pointerDownCount = 0;
    var pointerMoveCount = 0;
    var pointerUpCount = 0;
    var optionRequestCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DrawingCanvas(
                strokes: const [],
                onPointerDown: (_) => pointerDownCount += 1,
                onPointerMove: (_) => pointerMoveCount += 1,
                onPointerUp: (_) => pointerUpCount += 1,
              ),
              AiQuestionBubbleOverlay(
                question: _question,
                visible: true,
                selectedOptionId: null,
                onOptionSelected: (_) => optionRequestCount += 1,
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

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('ai-question-overlay-scroll')),
    );
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    expect(overlayRect.width, lessThan(canvasRect.width));
    expect(overlayRect.height, lessThan(canvasRect.height));

    final canvasGesture = await tester.startGesture(
      Offset(canvasRect.left + 48, canvasRect.center.dy),
    );
    await canvasGesture.moveBy(const Offset(40, 24));
    await canvasGesture.up();
    await tester.pump();

    expect(pointerDownCount, 1);
    expect(pointerMoveCount, greaterThan(0));
    expect(pointerUpCount, 1);

    await tester.tap(find.byKey(const ValueKey('ai-question-option-1')));
    await tester.pump();

    expect(optionRequestCount, 1);
    expect(pointerDownCount, 1);
    expect(pointerMoveCount, greaterThan(0));
    expect(pointerUpCount, 1);
    expect(tester.takeException(), isNull);
  });
}

final _question = AiQuestion(
  messageId: 10,
  conversationId: 20,
  sequence: 1,
  text: '그림에는 누가 함께 있어?',
  options: const [
    AiQuestionOption(
      optionId: '1',
      type: 'TEXT',
      label: '가족이 있어',
      value: '가족이 있어',
    ),
    AiQuestionOption(
      optionId: '2',
      type: 'TEXT',
      label: '친구가 있어',
      value: '친구가 있어',
    ),
  ],
  ttsAvailable: true,
  createdAt: DateTime(2026, 7, 23),
);

final _longQuestion = AiQuestion(
  messageId: 11,
  conversationId: 20,
  sequence: 2,
  text: '그림 속 가족은 지금 무엇을 하고 있고, 함께 있는 동물 친구는 어떤 기분인지 천천히 이야기해 줄래?',
  options: const [
    AiQuestionOption(
      optionId: 'long-1',
      type: 'TEXT',
      label: '엄마 아빠와 함께 저녁을 준비하고 있어',
      value: '엄마 아빠와 함께 저녁을 준비하고 있어',
    ),
    AiQuestionOption(
      optionId: 'long-2',
      type: 'TEXT',
      label: '강아지와 마당에서 신나게 뛰어놀고 있어',
      value: '강아지와 마당에서 신나게 뛰어놀고 있어',
    ),
    AiQuestionOption(
      optionId: 'long-3',
      type: 'TEXT',
      label: '모두 소파에 앉아서 이야기를 나누고 있어',
      value: '모두 소파에 앉아서 이야기를 나누고 있어',
    ),
  ],
  ttsAvailable: true,
  createdAt: DateTime(2026, 7, 23),
);

final class _FakeVoiceRecorder implements VoiceRecorder {
  @override
  Future<void> start() async {}

  @override
  Future<double> readAmplitude() async => -20;

  @override
  Future<String?> stop() async => '/tmp/voice-answer.m4a';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
