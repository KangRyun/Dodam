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
    await _waitForNoSpeechActions(tester);

    expect(find.text('무엇을 그렸어?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-recording-toggle')),
      findsOneWidget,
    );
    // 자동 녹음에서 3초간 음성이 없으면 모든 대체 응답 수단을 노출한다.
    expect(find.byKey(const ValueKey('ai-question-option-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-skip')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-conversation-end')), findsOneWidget);
    expect(find.textContaining('TTS_'), findsNothing);
    expect(find.textContaining('서버'), findsNothing);
    // 한 번 더 시도한다. 실측 실패의 상당수가 순간적인 게이트웨이·네트워크 흔들림이라
    //   같은 요청을 곧바로 다시 보내면 소리가 난다(P0-3).
    expect(ttsRepository.messageIds, [9001, 9001]);
    // 서버도 기기 음성도 실패했으면 직접 눌러 들을 길이 남아야 한다. 글을 못 읽는
    //   아이에게 이 버튼이 없으면 질문은 화면의 글자로만 남는다.
    expect(
      find.byKey(const ValueKey('question-tts-replay')),
      findsOneWidget,
    );
  });

  testWidgets('다시 들려줘를 누르면 실패한 질문을 다시 읽어 준다', (tester) async {
    final ttsRepository = _TtsRepository(failure: StateError('failed'));

    await _pumpConversation(
      tester,
      ttsRepository: ttsRepository,
      player: _Player(),
    );
    await _waitForNoSpeechActions(tester);
    expect(ttsRepository.messageIds, [9001, 9001]);

    final replay = find.byKey(const ValueKey('question-tts-replay'));
    await tester.ensureVisible(replay);
    await tester.tap(replay);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 자동 재생 가드를 지나쳐야 버튼이 제 역할을 한다. 예전에는 messageId 가드에
    //   막혀 눌러도 아무 일도 일어나지 않았다(2026-08-08 실측).
    expect(ttsRepository.messageIds.length, greaterThan(2));
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

  testWidgets('질문 건너뛰기는 요청 전에 TTS를 중단한다', (tester) async {
    final player = _Player();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: player,
    );
    await _waitForNoSpeechActions(tester);
    final stopsBeforeAction = player.stopCount;

    final action = find.byKey(const ValueKey('ai-question-skip'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();

    expect(player.stopCount, greaterThan(stopsBeforeAction));
  });

  testWidgets('대화 종료 확인 후 TTS를 중단한다', (tester) async {
    final player = _Player();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: player,
    );
    await _waitForNoSpeechActions(tester);
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
        voiceRecorder: _SilentRecorder(),
        microphonePermissionService: const _GrantedMicrophonePermission(),
        voiceNoSpeechTimeout: const Duration(milliseconds: 100),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _waitForNoSpeechActions(WidgetTester tester) async {
  final skip = find.byKey(const ValueKey('ai-question-skip'));
  final recording = find.textContaining('녹음 끝내기');
  for (
    var attempt = 0;
    attempt < 24 && recording.evaluate().isEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  for (var attempt = 0; attempt < 20 && skip.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
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
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async => const ConversationStartResult(
    conversationId: 8001,
    maxQuestionCount: 5,
  );

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

final class _SilentRecorder implements VoiceRecorder {
  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => '/tmp/voice-answer.m4a';

  @override
  Future<void> cancel() async {}

  @override
  Future<double> readAmplitude() async => -80;

  @override
  Future<void> dispose() async {}
}

final class _GrantedMicrophonePermission
    implements MicrophonePermissionService {
  const _GrantedMicrophonePermission();

  @override
  Future<MicrophonePermissionStatus> request() async =>
      MicrophonePermissionStatus.granted;

  @override
  Future<bool> openSettings() async => true;
}
