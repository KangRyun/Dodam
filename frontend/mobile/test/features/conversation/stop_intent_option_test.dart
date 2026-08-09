import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 아이가 말로 그만하겠다고 하면 AI 가 무엇을 그만할지 되묻고, 그 답을 실제 종료로
/// 옮기는 흐름을 검사한다 (S15P11B209-938 칩 · S15P11B209-951 음성).
///
/// 두 종료는 무게가 다르다. 대화 종료는 그림을 계속 그릴 수 있어 가볍지만, 그림 활동
/// 완료는 되돌릴 수 없다. 그래서 칩 하나가 잘못 연결되면 아이가 이야기만 그만하려다
/// 그림까지 끝내 버린다 — 여기서 잡는다.
void main() {
  testWidgets('말로 확인한 대화 종료는 화면에 띄우지 않고 대화를 끝낸다', (tester) async {
    // 되묻기에 "응"이라고 말하면 서버가 맺음말에 confirmedStopTarget 을 실어 보낸다(951).
    // 이건 질문이 아니라 대화를 닫는 말이므로 답을 기다리지 않는다.
    final repository = _ConversationRepository([_conversationClosing]);
    final ends = _EndRepository();
    await _pumpConversation(
      tester,
      repository: repository,
      endRepository: ends,
      awaitQuestion: false,
    );

    await _pumpUntilCall(() => ends.requests.isNotEmpty, tester);
    expect(ends.requests.single.reason, ConversationCompletionReason.childRequest);
    expect(find.text(_conversationClosing.text), findsNothing);
    // 종료했으니 다음 질문을 더 만들지 않는다(최초 1건 그대로).
    expect(repository.requests, hasLength(1));
  });

  testWidgets('말로 확인한 활동 완료는 대화 종료 API 를 직접 부르지 않는다', (tester) async {
    // 활동 완료는 기존 '다 그렸어요!' 확인·회고 흐름을 그대로 탄다 — 칩 경로와 같다.
    final repository = _ConversationRepository([_activityClosing]);
    final ends = _EndRepository();
    await _pumpConversation(
      tester,
      repository: repository,
      endRepository: ends,
      awaitQuestion: false,
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(ends.requests, isEmpty);
    expect(repository.requests, hasLength(1));
  });

  testWidgets('모르는 종료 대상은 평범한 질문으로 다룬다', (tester) async {
    // 서버가 새 대상을 먼저 배포해도 구버전 앱이 엉뚱한 것을 끝내지 않는다.
    final repository = _ConversationRepository([_unknownTargetQuestion]);
    final ends = _EndRepository();
    await _pumpConversation(
      tester,
      repository: repository,
      endRepository: ends,
      initialQuestion: _unknownTargetQuestion,
    );

    expect(ends.requests, isEmpty);
  });

  testWidgets('이야기만 그만할래 칩은 대화를 종료하고 다음 질문을 요청하지 않는다', (tester) async {
    final repository = _ConversationRepository([_stopAskQuestion]);
    final ends = _EndRepository();
    await _pumpConversation(tester, repository: repository, endRepository: ends);

    await _tapOption(tester, 'CHIP_END_TALK');

    await _pumpUntilCall(() => ends.requests.isNotEmpty, tester);
    expect(ends.requests.single.reason, ConversationCompletionReason.childRequest);
    // 종료했으니 다음 질문을 더 만들지 않는다(최초 1건 그대로).
    expect(repository.requests, hasLength(1));
  });

  testWidgets('그림 다 그렸어 칩은 대화 종료 API 를 직접 부르지 않는다', (tester) async {
    // 활동 완료는 기존 '다 그렸어요!' 확인·회고 흐름을 그대로 탄다. 그림 내용이 없는
    // 이 화면에서는 그 흐름이 시작 전에 멈추므로, 여기서 확인하는 것은 '대화 종료로
    // 잘못 새지 않는가'와 '다음 질문을 요청하지 않는가' 둘이다.
    final repository = _ConversationRepository([_stopAskQuestion]);
    final ends = _EndRepository();
    await _pumpConversation(tester, repository: repository, endRepository: ends);

    await _tapOption(tester, 'CHIP_END_ACTIVITY');
    await tester.pump(const Duration(milliseconds: 50));

    expect(ends.requests, isEmpty);
    expect(repository.requests, hasLength(1));
  });

  testWidgets('아니 더 할래 칩은 대화를 잇는다', (tester) async {
    final repository = _ConversationRepository([
      _stopAskQuestion,
      _followUpQuestion,
    ]);
    final ends = _EndRepository();
    await _pumpConversation(tester, repository: repository, endRepository: ends);

    await _tapOption(tester, 'CHIP_KEEP_GOING');

    await _pumpUntil(tester, find.text(_followUpQuestion.text));
    expect(ends.requests, isEmpty);
    expect(repository.requests, hasLength(2));
  });

  testWidgets('평범한 칩은 종료 신호로 다루지 않는다', (tester) async {
    final repository = _ConversationRepository([
      _ordinaryQuestion,
      _followUpQuestion,
    ]);
    final ends = _EndRepository();
    await _pumpConversation(
      tester,
      repository: repository,
      endRepository: ends,
      initialQuestion: _ordinaryQuestion,
    );

    await _tapOption(tester, 'CHIP_YES');

    await _pumpUntil(tester, find.text(_followUpQuestion.text));
    expect(ends.requests, isEmpty);
    expect(repository.requests, hasLength(2));
  });
}

Future<void> _tapOption(WidgetTester tester, String optionId) async {
  final option = find.byKey(ValueKey('ai-question-option-$optionId'));
  await _pumpUntil(tester, option);
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pump();
}

Future<void> _pumpConversation(
  WidgetTester tester, {
  required _ConversationRepository repository,
  required _EndRepository endRepository,
  AiQuestion? initialQuestion,
  bool awaitQuestion = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '1',
        sessionId: 100,
        conversationRepository: repository,
        conversationAnswerRepository: _AnswerRepository(),
        questionSkipRepository: _SkipRepository(),
        conversationEndRepository: endRepository,
        conversationId: 8001,
        resumeConversation: true,
        questionOptionRevealDelay: Duration.zero,
        noResponseTimeout: const Duration(seconds: 30),
        voiceRecorder: _VoiceRecorder(),
        microphonePermissionService: const _GrantedMicrophonePermission(),
      ),
    ),
  );
  await tester.pump();
  if (!awaitQuestion) {
    // 맺음말은 화면에 뜨지 않으므로 텍스트를 기다리면 안 된다 — 몇 프레임만 돌린다.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    return;
  }
  await _pumpUntil(
    tester,
    find.text((initialQuestion ?? _stopAskQuestion).text),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 60,
}) async {
  for (var frame = 0; frame < maxFrames && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilCall(
  bool Function() predicate,
  WidgetTester tester, {
  int maxFrames = 60,
}) async {
  for (var frame = 0; frame < maxFrames && !predicate(); frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(predicate(), isTrue);
}

final class _ConversationRepository implements ConversationRepository {
  _ConversationRepository(this.outcomes);

  final List<AiQuestion> outcomes;
  final List<NextQuestionRequest> requests = [];

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
  }) async {
    final index = requests.length;
    requests.add(request);
    return outcomes[index.clamp(0, outcomes.length - 1)];
  }
}

final class _AnswerRepository implements ConversationAnswerRepository {
  final List<OptionAnswerRequest> requests = [];

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    requests.add(request);
    return const OptionAnswerResult(answerMessageId: 9101);
  }
}

final class _SkipRepository implements QuestionSkipRepository {
  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async => const QuestionSkipResult(skipped: true);
}

final class _EndRepository implements ConversationEndRepository {
  final List<ConversationEndRequest> requests = [];

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    requests.add(request);
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: 'CHILD_REQUEST',
      completedAt: '2026-08-05T00:00:00Z',
      nextStage: 'REFLECTION',
    );
  }
}

final class _VoiceRecorder implements VoiceRecorder {
  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => null;

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

/// AI 가 "무엇을 그만할까?"라고 되물으며 보낸 질문 (question_service.STOP_ASK_BOTH).
final _stopAskQuestion = AiQuestion(
  messageId: 9001,
  conversationId: 8001,
  sequence: 1,
  text: '그래! 그림을 그만 그릴까, 아니면 이야기만 그만할까?',
  options: const [
    AiQuestionOption(
      optionId: 'CHIP_END_ACTIVITY',
      type: 'OPTION',
      label: '그림 다 그렸어',
      value: 'CHIP_END_ACTIVITY',
    ),
    AiQuestionOption(
      optionId: 'CHIP_END_TALK',
      type: 'OPTION',
      label: '이야기만 그만할래',
      value: 'CHIP_END_TALK',
    ),
    AiQuestionOption(
      optionId: 'CHIP_KEEP_GOING',
      type: 'OPTION',
      label: '아니, 더 할래',
      value: 'CHIP_KEEP_GOING',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 5),
);

/// 아이가 되묻기에 말로 "응"이라고 답해 서버가 보낸 맺음말 (S15P11B209-951).
final _conversationClosing = AiQuestion(
  messageId: 9011,
  conversationId: 8001,
  sequence: 1,
  text: '그래, 오늘 이야기 재미있었어. 그림은 계속 그려도 돼!',
  options: const [],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 5),
  confirmedStopTarget: confirmedStopConversation,
);

final _activityClosing = AiQuestion(
  messageId: 9012,
  conversationId: 8001,
  sequence: 1,
  text: '그래, 오늘 그림 정말 멋졌어. 다음에 또 그리자!',
  options: const [],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 5),
  confirmedStopTarget: confirmedStopActivity,
);

final _unknownTargetQuestion = AiQuestion(
  messageId: 9013,
  conversationId: 8001,
  sequence: 1,
  text: '이 나무는 몇 살이야?',
  options: const [],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 5),
  confirmedStopTarget: 'EVERYTHING',
);

final _ordinaryQuestion = AiQuestion(
  messageId: 9003,
  conversationId: 8001,
  sequence: 1,
  text: '이 사람은 누구야?',
  options: const [
    AiQuestionOption(
      optionId: 'CHIP_YES',
      type: 'OPTION',
      label: '응, 맞아!',
      value: 'CHIP_YES',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 5),
);

final _followUpQuestion = AiQuestion(
  messageId: 9002,
  conversationId: 8001,
  sequence: 2,
  text: '그럼 이 사람은 뭐 하고 있어?',
  options: const [
    AiQuestionOption(
      optionId: 'CHIP_TELL_MORE',
      type: 'OPTION',
      label: '더 이야기해 줄래',
      value: 'CHIP_TELL_MORE',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 5),
);
