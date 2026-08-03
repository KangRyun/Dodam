import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('입력 가능 후 timeout이면 다음 질문을 한 번만 요청한다', (tester) async {
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(seconds: 5),
    );

    await tester.pump(const Duration(seconds: 4));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));

    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.previousAnswerMessageId, isNull);
  });

  testWidgets('TTS 재생 시간은 timeout에 포함하지 않는다', (tester) async {
    final playback = Completer<void>();
    final player = _QuestionPlayer(playback: playback);
    final repository = _ConversationRepository([
      _initialQuestionWithTts,
      _candidateQuestion,
    ]);
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(seconds: 5),
      ttsRepository: _QuestionTtsRepository(),
      player: player,
    );
    await _pumpUntilCall(() => player.playCalls == 1, tester);

    await tester.pump(const Duration(seconds: 1));
    expect(repository.requests, hasLength(1));

    playback.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    expect(repository.requests, hasLength(2));
  });

  for (final scenario in ['failure', 'unsupported']) {
    testWidgets('TTS $scenario 상태에서도 timeout을 시작한다', (tester) async {
      final repository = _ConversationRepository([
        scenario == 'failure' ? _initialQuestionWithTts : _initialQuestion,
        _candidateQuestion,
      ]);
      await _pumpConversation(
        tester,
        repository: repository,
        ttsRepository: scenario == 'failure'
            ? _QuestionTtsRepository(failure: StateError('tts failed'))
            : null,
        player: scenario == 'failure' ? _QuestionPlayer() : null,
      );

      await tester.pump(const Duration(milliseconds: 100));
      await _pumpUntil(tester, find.text(_candidateQuestion.text));
      expect(repository.requests, hasLength(2));
    });
  }

  testWidgets('녹음 시작은 예약된 timeout을 취소한다', (tester) async {
    final repository = _ConversationRepository([_initialQuestion]);
    final recorder = _VoiceRecorder();
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(seconds: 5),
      recorder: recorder,
    );

    final record = find.byKey(const ValueKey('voice-recording-toggle'));
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pump();
    expect(recorder.startCalls, 1);

    await tester.pump(const Duration(seconds: 6));
    expect(repository.requests, hasLength(1));
  });

  testWidgets('자동 녹음 무음 후 후보가 입력 가능해지면 timeout을 시작한다', (tester) async {
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    final recorder = _VoiceRecorder();
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(milliseconds: 100),
      voiceNoSpeechTimeout: Duration.zero,
      recorder: recorder,
      voiceAnswerRepository: const _VoiceAnswerRepository(),
    );

    await tester.pump(const Duration(milliseconds: 150));
    expect(recorder.startCalls, 1);
    expect(repository.requests, hasLength(1));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('ai-question-option-ORIG_1')),
      maxFrames: 200,
    );
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 99));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    expect(repository.requests, hasLength(2));
  });

  testWidgets('후보 선택 연속 탭은 timer를 취소하고 한 번만 제출한다', (tester) async {
    final answer = Completer<OptionAnswerResult>();
    final answers = _AnswerRepository(result: answer.future);
    final repository = _ConversationRepository([_initialQuestion]);
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(seconds: 5),
      answerRepository: answers,
    );
    await tester.pump(const Duration(milliseconds: 2500));

    final option = find.byKey(const ValueKey('ai-question-option-ORIG_1'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.tap(option);
    await tester.pump();

    expect(answers.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 6));
    expect(repository.requests, hasLength(1));
  });

  testWidgets('건너뛰기는 timer를 취소한다', (tester) async {
    final skip = Completer<QuestionSkipResult>();
    final skips = _SkipRepository(result: skip.future);
    final repository = _ConversationRepository([_initialQuestion]);
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(seconds: 5),
      skipRepository: skips,
    );
    await tester.pump(const Duration(milliseconds: 2500));

    final button = find.byKey(const ValueKey('ai-question-skip'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(skips.callCount, 1);

    await tester.pump(const Duration(seconds: 6));
    expect(repository.requests, hasLength(1));
  });

  testWidgets('질문 변경은 이전 timer를 무효화한다', (tester) async {
    final answers = _AnswerRepository();
    final repository = _ConversationRepository([
      _initialQuestion,
      _secondQuestion,
    ]);
    await _pumpConversation(
      tester,
      repository: repository,
      timeout: const Duration(seconds: 5),
      maxQuestionCount: 2,
      answerRepository: answers,
    );
    await tester.pump(const Duration(milliseconds: 2500));
    final option = find.byKey(const ValueKey('ai-question-option-ORIG_1'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await _pumpUntil(tester, find.text(_secondQuestion.text));

    await tester.pump(const Duration(seconds: 6));
    expect(repository.requests, hasLength(2));
  });

  testWidgets('background에서는 자동 요청을 보내지 않는다', (tester) async {
    final repository = _ConversationRepository([_initialQuestion]);
    await _pumpConversation(tester, repository: repository);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.requests, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('자동 요청 중 background 전환은 늦은 결과를 무효화한다', (tester) async {
    final pending = Completer<AiQuestion>();
    final repository = _ConversationRepository([
      _initialQuestion,
      pending.future,
    ]);
    await _pumpConversation(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntilCall(() => repository.requests.length == 2, tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    pending.complete(_candidateQuestion);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text(_initialQuestion.text), findsOneWidget);
    expect(find.text(_candidateQuestion.text), findsNothing);
    expect(repository.requests, hasLength(2));
  });

  testWidgets('dispose 후에는 자동 요청을 보내지 않는다', (tester) async {
    final repository = _ConversationRepository([_initialQuestion]);
    await _pumpConversation(tester, repository: repository);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(repository.requests, hasLength(1));
  });

  testWidgets('resume 후 현재 질문에는 새 timeout을 시작한다', (tester) async {
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(tester, repository: repository);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    expect(repository.requests, hasLength(2));
  });

  testWidgets('서버 후보 개수와 순서 및 56dp 터치 영역을 그대로 렌더링한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    await tester.pump(const Duration(milliseconds: 2500));

    for (final option in _candidateQuestion.options) {
      final finder = find.byKey(
        ValueKey('ai-question-option-${option.optionId}'),
      );
      expect(finder, findsOneWidget);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      expect(find.text(option.label), findsOneWidget);
    }
    final positions = [
      for (final option in _candidateQuestion.options)
        tester.getTopLeft(
          find.byKey(ValueKey('ai-question-option-${option.optionId}')),
        ),
    ];
    expect(positions[0].dy, positions[1].dy);
    expect(positions[0].dx, lessThan(positions[1].dx));
    expect(positions[2].dy, greaterThan(positions[0].dy));
    expect(positions[2].dx, lessThan(positions[3].dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('서버 optionId value labelSnapshot을 변형 없이 제출한다', (tester) async {
    final answers = _AnswerRepository(
      result: Completer<OptionAnswerResult>().future,
    );
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(
      tester,
      repository: repository,
      answerRepository: answers,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    await tester.pump(const Duration(milliseconds: 2500));

    final option = find.byKey(const ValueKey('ai-question-option-CAND_2'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();

    final request = answers.requests.single;
    expect(request.questionMessageId, _candidateQuestion.messageId);
    expect(request.selectedOptions.single.optionId, 'CAND_2');
    expect(request.selectedOptions.single.value, 'server-value-2');
    expect((request.toJson()['selectedOptions'] as List).single, {
      'optionId': 'CAND_2',
      'type': 'STATIC',
      'value': 'server-value-2',
      'labelSnapshot': '서버 후보 둘',
    });
  });

  testWidgets('이 중에 없어도 서버 CAND_NONE 식별자와 labelSnapshot을 제출한다', (tester) async {
    final answers = _AnswerRepository(
      result: Completer<OptionAnswerResult>().future,
    );
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(
      tester,
      repository: repository,
      answerRepository: answers,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    await tester.pump(const Duration(milliseconds: 2500));

    final none = find.byKey(const ValueKey('ai-question-option-CAND_NONE'));
    await tester.ensureVisible(none);
    await tester.tap(none);
    await tester.pump();

    final json = answers.requests.single.toJson();
    expect((json['selectedOptions'] as List).single, {
      'optionId': 'CAND_NONE',
      'type': 'STATIC',
      'value': 'server-none',
      'labelSnapshot': '이 중에 없어',
    });
  });

  testWidgets('CHIP_NO 선택은 답변 ID로 후보 네 개를 한 번만 요청한다', (tester) async {
    const answerMessageId = 91719;
    final answers = _AnswerRepository(
      result: Future.value(
        const OptionAnswerResult(answerMessageId: answerMessageId),
      ),
    );
    final repository = _ConversationRepository([
      _chipNoQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(
      tester,
      repository: repository,
      initialQuestion: _chipNoQuestion,
      timeout: const Duration(seconds: 30),
      answerRepository: answers,
    );
    for (var rebuild = 0; rebuild < 4; rebuild += 1) {
      await tester.pump();
    }

    final chipNo = find.byKey(const ValueKey('ai-question-option-CHIP_NO'));
    expect(chipNo, findsOneWidget);
    expect(find.text(_chipNoQuestion.options.single.label), findsOneWidget);
    await tester.ensureVisible(chipNo);
    await tester.tap(chipNo);
    await tester.tap(chipNo);
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('ai-question-option-CAND_NONE')),
    );

    expect(answers.requests, hasLength(1));
    expect(
      (answers.requests.single.toJson()['selectedOptions'] as List).single,
      {
        'optionId': 'CHIP_NO',
        'type': 'STATIC',
        'value': 'server-negative-value',
        'labelSnapshot': '음, 아니야',
      },
    );
    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.previousAnswerMessageId, answerMessageId);

    expect(_candidateQuestion.options.map((option) => option.optionId), [
      'CAND_1',
      'CAND_2',
      'CAND_3',
      'CAND_NONE',
    ]);
    final positions = <Offset>[];
    for (final option in _candidateQuestion.options) {
      final finder = find.byKey(
        ValueKey('ai-question-option-${option.optionId}'),
      );
      expect(finder, findsOneWidget);
      expect(find.text(option.label), findsOneWidget);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      positions.add(tester.getTopLeft(finder));
    }
    expect(positions[0].dy, positions[1].dy);
    expect(positions[0].dx, lessThan(positions[1].dx));
    expect(positions[2].dy, greaterThan(positions[0].dy));
    expect(positions[2].dx, lessThan(positions[3].dx));
    expect(answers.requests, hasLength(1));
    expect(repository.requests, hasLength(2));
  });

  testWidgets('중복 rebuild와 callback에도 자동 요청은 한 번이다', (tester) async {
    final pending = Completer<AiQuestion>();
    final repository = _ConversationRepository([
      _initialQuestion,
      pending.future,
    ]);
    await _pumpConversation(tester, repository: repository);
    for (var index = 0; index < 8; index += 1) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(repository.requests, hasLength(2));

    pending.complete(_candidateQuestion);
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    expect(repository.requests, hasLength(2));
  });

  testWidgets('최대 질문 수에 도달하면 자동 요청을 만들지 않는다', (tester) async {
    final repository = _ConversationRepository([_initialQuestion]);
    await _pumpConversation(
      tester,
      repository: repository,
      maxQuestionCount: 1,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(repository.requests, hasLength(1));
  });

  testWidgets('무응답으로 받은 후보 질문에는 timer를 반복하지 않는다', (tester) async {
    final repository = _ConversationRepository([
      _initialQuestion,
      _candidateQuestion,
    ]);
    await _pumpConversation(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    await tester.pump(const Duration(seconds: 2));
    expect(repository.requests, hasLength(2));
  });

  testWidgets('자동 요청 실패는 기존 오류와 같은 Key 재시도 흐름을 유지한다', (tester) async {
    final repository = _ConversationRepository([
      _initialQuestion,
      const ApiTransportFailure(type: ApiTransportFailureType.connection),
      _candidateQuestion,
    ]);
    await _pumpConversation(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.byKey(const ValueKey('ai-question-error')));
    expect(find.textContaining('서버'), findsNothing);

    final retry = find.byKey(const ValueKey('ai-question-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await _pumpUntil(tester, find.text(_candidateQuestion.text));
    expect(repository.requests, hasLength(3));
    expect(repository.idempotencyKeys[1], repository.idempotencyKeys[2]);
  });

  testWidgets('시스템 back은 timer를 취소하고 route를 한 번만 pop한다', (tester) async {
    final repository = _ConversationRepository([_initialQuestion]);
    final navigatorKey = GlobalKey<NavigatorState>();
    var popCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('host')),
      ),
    );
    unawaited(
      navigatorKey.currentState!
          .push<void>(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => _screen(
                repository: repository,
                timeout: const Duration(seconds: 10),
              ),
            ),
          )
          .then((_) => popCount += 1),
    );
    await tester.pump();
    await tester.pump();
    await _pumpUntil(tester, find.text(_initialQuestion.text));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    expect(popCount, 1);
    expect(repository.requests, hasLength(1));
  });

  testWidgets('자동 요청 중 dispose 뒤 늦은 응답은 화면을 바꾸지 않는다', (tester) async {
    final pending = Completer<AiQuestion>();
    final repository = _ConversationRepository([
      _initialQuestion,
      pending.future,
    ]);
    await _pumpConversation(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.requests, hasLength(2));

    await tester.pumpWidget(const MaterialApp(home: Text('left')));
    pending.complete(_candidateQuestion);
    await tester.pump();
    expect(find.text(_candidateQuestion.text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('늦은 자동 응답은 사용자가 만든 새 질문을 덮어쓰지 않는다', (tester) async {
    final pending = Completer<AiQuestion>();
    final repository = _ConversationRepository([
      _initialQuestion,
      pending.future,
      _secondQuestion,
    ]);
    await _pumpConversation(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntilCall(() => repository.requests.length == 2, tester);
    await tester.pump(const Duration(milliseconds: 2500));

    final option = find.byKey(const ValueKey('ai-question-option-ORIG_1'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await _pumpUntil(tester, find.text(_secondQuestion.text));
    expect(repository.requests, hasLength(3));

    pending.complete(_candidateQuestion);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(_secondQuestion.text), findsOneWidget);
    expect(find.text(_candidateQuestion.text), findsNothing);
  });

  testWidgets('대화 생성에는 화면이 사용하는 maxQuestionCount를 전달한다', (tester) async {
    final repository = _ConversationRepository([_initialQuestion]);
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          childId: '1',
          sessionId: 100,
          conversationRepository: repository,
          resumeConversation: true,
          maxQuestionCount: 4,
          noResponseTimeout: const Duration(seconds: 30),
        ),
      ),
    );
    await tester.pump();
    await _pumpUntil(tester, find.text(_initialQuestion.text));
    expect(repository.startedMaxQuestionCounts, [4]);
  });
}

Future<void> _pumpConversation(
  WidgetTester tester, {
  required _ConversationRepository repository,
  AiQuestion? initialQuestion,
  Duration timeout = const Duration(milliseconds: 100),
  int maxQuestionCount = 10,
  _AnswerRepository? answerRepository,
  _SkipRepository? skipRepository,
  QuestionTtsRepository? ttsRepository,
  _QuestionPlayer? player,
  _VoiceRecorder? recorder,
  Duration voiceNoSpeechTimeout = const Duration(seconds: 3),
  VoiceAnswerRepository? voiceAnswerRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _screen(
        repository: repository,
        timeout: timeout,
        maxQuestionCount: maxQuestionCount,
        answerRepository: answerRepository,
        skipRepository: skipRepository,
        ttsRepository: ttsRepository,
        player: player,
        recorder: recorder,
        voiceNoSpeechTimeout: voiceNoSpeechTimeout,
        voiceAnswerRepository: voiceAnswerRepository,
      ),
    ),
  );
  await tester.pump();
  await _pumpUntil(
    tester,
    find.text((initialQuestion ?? _initialQuestion).text),
  );
}

Widget _screen({
  required _ConversationRepository repository,
  required Duration timeout,
  int maxQuestionCount = 10,
  _AnswerRepository? answerRepository,
  _SkipRepository? skipRepository,
  QuestionTtsRepository? ttsRepository,
  _QuestionPlayer? player,
  _VoiceRecorder? recorder,
  Duration voiceNoSpeechTimeout = const Duration(seconds: 3),
  VoiceAnswerRepository? voiceAnswerRepository,
}) => DrawingScreen(
  childId: '1',
  sessionId: 100,
  conversationRepository: repository,
  conversationAnswerRepository: answerRepository ?? _AnswerRepository(),
  questionSkipRepository: skipRepository ?? _SkipRepository(),
  conversationEndRepository: const _EndRepository(),
  conversationId: 8001,
  resumeConversation: true,
  questionOptionRevealDelay: Duration.zero,
  noResponseTimeout: timeout,
  maxQuestionCount: maxQuestionCount,
  voiceNoSpeechTimeout: voiceNoSpeechTimeout,
  voiceAnswerRepository: voiceAnswerRepository,
  questionTtsRepository: ttsRepository,
  questionAudioPlayerFactory: player == null ? null : () => player,
  voiceRecorder: recorder ?? _VoiceRecorder(),
  microphonePermissionService: const _GrantedMicrophonePermission(),
);

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
}) async {
  for (var frame = 0; frame < maxFrames && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilCall(
  bool Function() predicate,
  WidgetTester tester, {
  int maxFrames = 40,
}) async {
  for (var frame = 0; frame < maxFrames && !predicate(); frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(predicate(), isTrue);
}

final class _ConversationRepository implements ConversationRepository {
  _ConversationRepository(this.outcomes);

  final List<Object> outcomes;
  final List<NextQuestionRequest> requests = [];
  final List<String> idempotencyKeys = [];
  final List<int?> startedMaxQuestionCounts = [];

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async {
    startedMaxQuestionCounts.add(maxQuestionCount);
    return 8001;
  }

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    final index = requests.length;
    requests.add(request);
    idempotencyKeys.add(idempotencyKey);
    final outcome = outcomes[index.clamp(0, outcomes.length - 1)];
    if (outcome is Future<AiQuestion>) return outcome;
    if (outcome is AiQuestion) return outcome;
    throw outcome;
  }
}

final class _AnswerRepository implements ConversationAnswerRepository {
  _AnswerRepository({Future<OptionAnswerResult>? result})
    : result =
          result ??
          Future.value(const OptionAnswerResult(answerMessageId: 9101));

  final Future<OptionAnswerResult> result;
  final List<OptionAnswerRequest> requests = [];

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) {
    requests.add(request);
    return result;
  }
}

final class _SkipRepository implements QuestionSkipRepository {
  _SkipRepository({Future<QuestionSkipResult>? result})
    : result = result ?? Future.value(const QuestionSkipResult(skipped: true));

  final Future<QuestionSkipResult> result;
  int callCount = 0;

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) {
    callCount += 1;
    return result;
  }
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
    completedAt: '2026-08-03T00:00:00Z',
    nextStage: 'REFLECTION',
  );
}

final class _VoiceAnswerRepository implements VoiceAnswerRepository {
  const _VoiceAnswerRepository();

  @override
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  }) async => const VoiceAnswerUploadResult(
    messageId: 9201,
    parentMessageId: 9001,
    sequence: 2,
    speechStatus: 'TRANSCRIBED',
  );
}

final class _QuestionTtsRepository implements QuestionTtsRepository {
  _QuestionTtsRepository({this.failure});

  final Object? failure;

  @override
  Future<QuestionTtsAudio> loadQuestionAudio(
    int messageId, {
    QuestionTtsRequest request = const QuestionTtsRequest(),
  }) async {
    if (failure case final caught?) throw caught;
    return QuestionTtsAudio(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/mpeg',
    );
  }
}

final class _QuestionPlayer implements QuestionAudioPlayer {
  _QuestionPlayer({this.playback});

  final Completer<void>? playback;
  int playCalls = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCalls += 1;
    await playback?.future;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

final class _VoiceRecorder implements VoiceRecorder {
  int startCalls = 0;

  @override
  Future<void> start() async => startCalls += 1;

  @override
  Future<String?> stop() async => '/tmp/answer.m4a';

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

final _initialQuestion = AiQuestion(
  messageId: 9001,
  conversationId: 8001,
  sequence: 1,
  text: '처음 질문이야',
  options: const [
    AiQuestionOption(
      optionId: 'ORIG_1',
      type: 'OPTION',
      label: '처음 선택지',
      value: 'original-value',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 3),
);

final _initialQuestionWithTts = AiQuestion(
  messageId: 9001,
  conversationId: 8001,
  sequence: 1,
  text: _initialQuestion.text,
  options: _initialQuestion.options,
  ttsAvailable: true,
  createdAt: DateTime.utc(2026, 8, 3),
);

final _chipNoQuestion = AiQuestion(
  messageId: 9010,
  conversationId: 8001,
  sequence: 1,
  text: '이 집이 맞니?',
  options: const [
    AiQuestionOption(
      optionId: 'CHIP_NO',
      type: 'OPTION',
      label: '음, 아니야',
      value: 'server-negative-value',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 3),
);

final _candidateQuestion = AiQuestion(
  messageId: 9002,
  conversationId: 8001,
  sequence: 2,
  text: '그럼 보기에서 골라 줄래?',
  options: const [
    AiQuestionOption(
      optionId: 'CAND_1',
      type: 'OPTION',
      label: '서버 후보 하나',
      value: 'server-value-1',
    ),
    AiQuestionOption(
      optionId: 'CAND_2',
      type: 'OPTION',
      label: '서버 후보 둘',
      value: 'server-value-2',
    ),
    AiQuestionOption(
      optionId: 'CAND_3',
      type: 'OPTION',
      label: '서버 후보 셋',
      value: 'server-value-3',
    ),
    AiQuestionOption(
      optionId: 'CAND_NONE',
      type: 'OPTION',
      label: '이 중에 없어',
      value: 'server-none',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 3),
);

final _secondQuestion = AiQuestion(
  messageId: 9003,
  conversationId: 8001,
  sequence: 3,
  text: '두 번째 질문이야',
  options: const [],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 3),
);
