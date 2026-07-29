import 'dart:typed_data';

import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TTS 실패와 무관하게 질문과 모든 대화 조작을 유지한다', (tester) async {
    final ttsRepository = _TtsRepository(failure: StateError('failed'));

    await _pumpConversation(
      tester,
      ttsRepository: ttsRepository,
      player: _Player(),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('무엇을 그렸어?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-recording-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-question-option-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-skip')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-conversation-end')), findsOneWidget);
    expect(find.textContaining('TTS_'), findsNothing);
    expect(find.textContaining('서버'), findsNothing);
    expect(ttsRepository.messageIds, [9001]);
  });

  testWidgets('앱 lifecycle pause는 재생을 중단하고 복귀 시 다시 재생하지 않는다', (tester) async {
    final player = _Player();
    final ttsRepository = _TtsRepository();

    await _pumpConversation(
      tester,
      ttsRepository: ttsRepository,
      player: player,
    );
    expect(player.playCount, 1);
    final stopCount = player.stopCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(player.stopCount, greaterThan(stopCount));
    expect(player.playCount, 1);
    expect(ttsRepository.messageIds, [9001]);
  });

  testWidgets('선택지 답변과 skip은 요청 전에 TTS를 중단한다', (tester) async {
    for (final actionKey in [
      const ValueKey('ai-question-option-1'),
      const ValueKey('ai-question-skip'),
    ]) {
      final player = _Player();
      await _pumpConversation(
        tester,
        ttsRepository: _TtsRepository(),
        player: player,
      );
      await tester.pump(const Duration(seconds: 3));
      final stopsBeforeAction = player.stopCount;

      final action = find.byKey(actionKey);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();

      expect(player.stopCount, greaterThan(stopsBeforeAction));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('대화 종료 확인 후 TTS를 중단한다', (tester) async {
    final player = _Player();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: player,
    );
    final stopsBeforeAction = player.stopCount;

    final end = find.byKey(const ValueKey('ai-conversation-end'));
    await tester.ensureVisible(end);
    await tester.tap(end);
    await tester.pump();
    await tester.tap(find.text('대화 그만하기'));
    await tester.pump();

    expect(player.stopCount, greaterThan(stopsBeforeAction));
  });

  testWidgets('화면 dispose 시 재생을 중단하고 Player를 해제한다', (tester) async {
    final player = _Player();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: player,
    );
    final stopsBeforeDispose = player.stopCount;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(player.stopCount, greaterThan(stopsBeforeDispose));
    expect(player.disposeCount, 1);
  });
}

Future<void> _pumpConversation(
  WidgetTester tester, {
  required QuestionTtsRepository ttsRepository,
  required _Player player,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '1',
        sessionId: 100,
        conversationRepository: _ConversationRepository(),
        conversationAnswerRepository: const _AnswerRepository(),
        questionSkipRepository: const _SkipRepository(),
        conversationEndRepository: const _EndRepository(),
        conversationId: 8001,
        resumeConversation: true,
        questionTtsRepository: ttsRepository,
        questionAudioPlayerFactory: () => player,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final class _AnswerRepository implements ConversationAnswerRepository {
  const _AnswerRepository();

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async => const OptionAnswerResult(answerMessageId: 9101);
}

final class _SkipRepository implements QuestionSkipRepository {
  const _SkipRepository();

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async => const QuestionSkipResult(skipped: true);
}

final class _EndRepository implements ConversationEndRepository {
  const _EndRepository();

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async => ConversationEndResult(
    conversationId: conversationId,
    conversationStatus: 'COMPLETED',
    completed: true,
    completionReason: 'CHILD_REQUEST',
    completedAt: '2026-07-29T00:00:00Z',
    nextStage: 'REFLECTION',
  );
}

final class _ConversationRepository implements ConversationRepository {
  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 8001;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async => AiQuestion(
    messageId: 9001,
    conversationId: conversationId,
    sequence: 1,
    text: '무엇을 그렸어?',
    options: const [
      AiQuestionOption(
        optionId: '1',
        type: 'EMOJI',
        label: '가족',
        value: 'FAMILY',
      ),
    ],
    ttsAvailable: true,
    createdAt: DateTime.utc(2026, 7, 29),
  );
}

final class _TtsRepository implements QuestionTtsRepository {
  _TtsRepository({this.failure});

  final Object? failure;
  final List<int> messageIds = [];

  @override
  Future<QuestionTtsAudio> loadQuestionAudio(
    int messageId, {
    QuestionTtsRequest request = const QuestionTtsRequest(),
  }) async {
    messageIds.add(messageId);
    if (failure case final caught?) throw caught;
    return QuestionTtsAudio(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/mpeg',
    );
  }
}

final class _Player implements QuestionAudioPlayer {
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
