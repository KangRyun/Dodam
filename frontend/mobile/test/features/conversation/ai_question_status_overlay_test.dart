import 'dart:async';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_crayon_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('idle renders no mascot and cannot intercept the canvas', (
    tester,
  ) async {
    final displayController = AiQuestionDisplayController();
    addTearDown(displayController.dispose);

    await _pumpOverlay(
      tester,
      controller: null,
      displayController: displayController,
    );

    expect(
      find.byKey(const ValueKey('ai-question-status-content')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-question-status-character')),
      findsNothing,
    );
    final hitTestLayer = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('ai-question-status-hit-test')),
    );
    expect(hitTestLayer.ignoring, isTrue);
  });

  testWidgets(
    'conversation start presents the approved drawing mascot passively',
    (tester) async {
      final displayController = AiQuestionDisplayController();
      addTearDown(displayController.dispose);

      await _pumpOverlay(
        tester,
        controller: null,
        displayController: displayController,
        conversationStartInFlight: true,
      );

      expect(
        find.byKey(const ValueKey('ai-question-preparing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ai-question-status-character')),
        findsOneWidget,
      );
      final mascot = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('ai-question-status-character')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (mascot.image as AssetImage).assetName,
        'assets/characters/dodam_drawing.png',
      );
      final hitTestLayer = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('ai-question-status-hit-test')),
      );
      expect(hitTestLayer.ignoring, isTrue);
    },
  );

  testWidgets(
    'preparing stays contained in the 844x390 landscape canvas frame at 2x text',
    (tester) async {
      final displayController = AiQuestionDisplayController();
      addTearDown(displayController.dispose);

      await _pumpLandscapeOverlayInCanvasFrame(
        tester,
        controller: null,
        displayController: displayController,
        conversationStartInFlight: true,
      );

      expect(
        find.byKey(const ValueKey('ai-question-preparing')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      _expectContainedInLandscapeCanvas(
        tester,
        find.byKey(const ValueKey('ai-question-status-character')),
      );
    },
  );

  testWidgets(
    'retryable failure stays contained in the 844x390 landscape canvas frame at 2x text',
    (tester) async {
      final displayController = AiQuestionDisplayController();
      var retryCount = 0;
      addTearDown(displayController.dispose);

      await _pumpLandscapeOverlayInCanvasFrame(
        tester,
        controller: null,
        displayController: displayController,
        conversationStartError: const ApiTransportFailure(
          type: ApiTransportFailureType.connection,
        ),
        onRetryConversationStart: () => retryCount += 1,
      );

      expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
      final retry = find.byKey(const ValueKey('ai-question-retry'));
      expect(retry, findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectContainedInLandscapeCanvas(tester, retry);

      await tester.tap(retry);
      expect(retryCount, 1);
    },
  );

  testWidgets('default preparing presentation ends at 2500 milliseconds', (
    tester,
  ) async {
    final displayController = AiQuestionDisplayController();
    addTearDown(displayController.dispose);

    await _pumpOverlay(
      tester,
      controller: null,
      displayController: displayController,
      conversationStartInFlight: true,
    );

    await tester.pump(const Duration(milliseconds: 2499));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);
  });

  testWidgets('question loading is visible until its presentation cap', (
    tester,
  ) async {
    final pendingQuestion = Completer<AiQuestion>();
    final controller = AiQuestionController(
      _ConversationRepository(pendingQuestion.future),
      conversationId: 11,
    );
    final displayController = AiQuestionDisplayController();
    addTearDown(controller.dispose);
    addTearDown(displayController.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
      maxPreparingDuration: const Duration(seconds: 1),
    );

    expect(controller.isLoading, isTrue);
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 999));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);
    expect(controller.isLoading, isTrue);
  });

  testWidgets('quick question success dismisses preparing immediately', (
    tester,
  ) async {
    final pendingQuestion = Completer<AiQuestion>();
    final controller = AiQuestionController(
      _ConversationRepository(pendingQuestion.future),
      conversationId: 11,
    );
    final displayController = AiQuestionDisplayController();
    addTearDown(controller.dispose);
    addTearDown(displayController.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
      maxPreparingDuration: const Duration(seconds: 1),
    );
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);

    pendingQuestion.complete(_question);
    await tester.pump();

    expect(controller.status, AiQuestionStatus.success);
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);
  });

  testWidgets('failure appears after the cap and persists for retry', (
    tester,
  ) async {
    final pendingQuestion = Completer<AiQuestion>();
    final controller = AiQuestionController(
      _ConversationRepository(pendingQuestion.future),
      conversationId: 11,
    );
    final displayController = AiQuestionDisplayController();
    addTearDown(controller.dispose);
    addTearDown(displayController.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
      maxPreparingDuration: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);

    pendingQuestion.completeError(
      const ApiTransportFailure(type: ApiTransportFailureType.connection),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.status, AiQuestionStatus.failure);
    expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-retry')), findsOneWidget);
    final hitTestLayer = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('ai-question-status-hit-test')),
    );
    expect(hitTestLayer.ignoring, isFalse);

    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
  });

  testWidgets('failure has no decorative mascot semantics node', (
    tester,
  ) async {
    final displayController = AiQuestionDisplayController();
    final controller = AiQuestionController(
      _ConversationRepository(Future<AiQuestion>.error(StateError('offline'))),
      conversationId: 1,
    );
    addTearDown(displayController.dispose);
    addTearDown(controller.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
    );
    await tester.pump();
    await tester.pump();

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('assets/characters/dodam_drawing.png'),
      findsNothing,
    );
    final mascot = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('ai-question-status-character')),
        matching: find.byType(Image),
      ),
    );
    expect(mascot.excludeFromSemantics, isTrue);
    semantics.dispose();
  });

  testWidgets('an actual question replaces the preparing status immediately', (
    tester,
  ) async {
    final pendingQuestion = Completer<AiQuestion>();
    final controller = AiQuestionController(
      _ConversationRepository(pendingQuestion.future),
      conversationId: 11,
    );
    final displayController = AiQuestionDisplayController();
    addTearDown(controller.dispose);
    addTearDown(displayController.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
    );
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);

    displayController.receive(_question);
    await tester.pump();

    expect(displayController.hasUnresolvedQuestion, isTrue);
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-question-status-character')),
      findsNothing,
    );
  });

  testWidgets('retry starts a fresh generation-bound presentation cap', (
    tester,
  ) async {
    final firstAttempt = Completer<AiQuestion>();
    final retryAttempt = Completer<AiQuestion>();
    final controller = AiQuestionController(
      _SequencedConversationRepository([
        firstAttempt.future,
        retryAttempt.future,
      ]),
      conversationId: 11,
    );
    final displayController = AiQuestionDisplayController();
    addTearDown(controller.dispose);
    addTearDown(displayController.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
      maxPreparingDuration: const Duration(seconds: 1),
      onRetryQuestion: () => unawaited(controller.load()),
    );
    await tester.pump(const Duration(milliseconds: 600));

    firstAttempt.completeError(
      const ApiTransportFailure(type: ApiTransportFailureType.connection),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-question-retry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 599));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);
    expect(controller.isLoading, isTrue);
  });

  testWidgets('controller replacement gives the new source a fresh cap', (
    tester,
  ) async {
    final oldPending = Completer<AiQuestion>();
    final newPending = Completer<AiQuestion>();
    final oldController = AiQuestionController(
      _ConversationRepository(oldPending.future),
      conversationId: 11,
    );
    final newController = AiQuestionController(
      _ConversationRepository(newPending.future),
      conversationId: 11,
    );
    final oldDisplay = AiQuestionDisplayController();
    final newDisplay = AiQuestionDisplayController();
    addTearDown(oldController.dispose);
    addTearDown(newController.dispose);
    addTearDown(oldDisplay.dispose);
    addTearDown(newDisplay.dispose);

    unawaited(oldController.load());
    await _pumpOverlay(
      tester,
      controller: oldController,
      displayController: oldDisplay,
      maxPreparingDuration: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(newController.load());
    await _pumpOverlay(
      tester,
      controller: newController,
      displayController: newDisplay,
      maxPreparingDuration: const Duration(seconds: 1),
    );
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);

    oldDisplay.receive(_question);
    oldPending.complete(_question);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 599));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('ai-question-preparing')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels an active preparing callback', (tester) async {
    final pending = Completer<AiQuestion>();
    final controller = AiQuestionController(
      _ConversationRepository(pending.future),
      conversationId: 11,
    );
    final displayController = AiQuestionDisplayController();
    addTearDown(controller.dispose);
    addTearDown(displayController.dispose);

    unawaited(controller.load());
    await _pumpOverlay(
      tester,
      controller: controller,
      displayController: displayController,
      maxPreparingDuration: const Duration(seconds: 1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation-start failure uses its captured retry callback', (
    tester,
  ) async {
    final displayController = AiQuestionDisplayController();
    var retryCount = 0;
    addTearDown(displayController.dispose);

    await _pumpOverlay(
      tester,
      controller: null,
      displayController: displayController,
      conversationStartError: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
      onRetryConversationStart: () => retryCount += 1,
    );

    expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-question-retry')));
    expect(retryCount, 1);
  });

  testWidgets('non-retryable failure leaves the whole status layer passive', (
    tester,
  ) async {
    final displayController = AiQuestionDisplayController();
    addTearDown(displayController.dispose);

    await _pumpOverlay(
      tester,
      controller: null,
      displayController: displayController,
      conversationStartError: const ApiResponseFailure(
        statusCode: 403,
        error: null,
      ),
    );

    expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-retry')), findsNothing);
    final hitTestLayer = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('ai-question-status-hit-test')),
    );
    expect(hitTestLayer.ignoring, isTrue);
  });
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required AiQuestionController? controller,
  required AiQuestionDisplayController displayController,
  bool conversationStartInFlight = false,
  Object? conversationStartError,
  VoidCallback? onRetryConversationStart,
  VoidCallback? onRetryQuestion,
  Duration maxPreparingDuration = const Duration(milliseconds: 2500),
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          AiQuestionStatusOverlay(
            controller: controller,
            displayController: displayController,
            conversationStartInFlight: conversationStartInFlight,
            conversationStartError: conversationStartError,
            onRetryConversationStart: onRetryConversationStart ?? () {},
            onRetryQuestion: onRetryQuestion ?? () {},
            maxPreparingDuration: maxPreparingDuration,
          ),
        ],
      ),
    ),
  ),
);

Future<void> _pumpLandscapeOverlayInCanvasFrame(
  WidgetTester tester, {
  required AiQuestionController? controller,
  required AiQuestionDisplayController displayController,
  bool conversationStartInFlight = false,
  Object? conversationStartError,
  VoidCallback? onRetryConversationStart,
}) async {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        appBar: const AppTopBar(title: 'Drawing'),
        body: Column(
          children: [
            const SizedBox(height: 60),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: DrawingCrayonFrame(
                  deviceClass: DrawingCanvasDeviceClass.mobileLandscape,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AiQuestionStatusOverlay(
                        controller: controller,
                        displayController: displayController,
                        conversationStartInFlight: conversationStartInFlight,
                        conversationStartError: conversationStartError,
                        onRetryConversationStart:
                            onRetryConversationStart ?? () {},
                        onRetryQuestion: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _expectContainedInLandscapeCanvas(WidgetTester tester, Finder finder) {
  final canvasRect = tester.getRect(
    find.byKey(const ValueKey('drawing-crayon-document')),
  );
  final childRect = tester.getRect(finder);
  expect(childRect.left, greaterThanOrEqualTo(canvasRect.left));
  expect(childRect.top, greaterThanOrEqualTo(canvasRect.top));
  expect(childRect.right, lessThanOrEqualTo(canvasRect.right));
  expect(childRect.bottom, lessThanOrEqualTo(canvasRect.bottom));
}

final class _ConversationRepository implements ConversationRepository {
  const _ConversationRepository(this.result);

  final Future<AiQuestion> result;

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 11;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) => result;
}

final class _SequencedConversationRepository implements ConversationRepository {
  _SequencedConversationRepository(this.results);

  final List<Future<AiQuestion>> results;
  int _callCount = 0;

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 11;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) => results[_callCount++];
}

final _question = AiQuestion(
  messageId: 41,
  conversationId: 11,
  sequence: 1,
  text: '그림에서 무엇이 가장 궁금해?',
  options: const [],
  ttsAvailable: true,
  createdAt: DateTime.utc(2026, 7, 31),
);
