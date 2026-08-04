import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
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
  testWidgets(
    'late TTS completion cannot restart recording after skip begins',
    (tester) async {
      final player = _PendingPlayer();
      final recorder = _CountingRecorder();
      final skips = _PendingSkipRepository();
      await _pumpConversation(
        tester,
        ttsRepository: _TtsRepository(),
        player: player,
        voiceRecorder: recorder,
        voiceAnswerRepository: _VoiceAnswerRepository.success(),
        questionSkipRepository: skips,
      );
      await tester.pump();

      final skip = find.byKey(const ValueKey('ai-question-skip'));
      await tester.ensureVisible(skip);
      await tester.tap(skip);
      await tester.pump();
      expect(skips.pending, isNotNull);

      player.complete();
      await tester.pump();

      expect(recorder.startCount, 0);
    },
  );

  testWidgets(
    'lifecycle pause interrupts active recording and reveals fallback',
    (tester) async {
      final recorder = _CountingRecorder();
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await _pumpConversation(
        tester,
        ttsRepository: _TtsRepository(),
        player: _Player(),
        voiceRecorder: recorder,
        voiceAnswerRepository: _VoiceAnswerRepository.success(),
        voiceNoSpeechTimeout: const Duration(seconds: 30),
      );
      await _waitForActiveRecording(tester);
      final cancelCountBeforePause = recorder.cancelCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();

      expect(recorder.cancelCount, cancelCountBeforePause + 1);
      expect(
        find.byKey(const ValueKey('ai-question-option-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('drawing back action cancels active recording before exit', (
    tester,
  ) async {
    final recorder = _CountingRecorder();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: recorder,
      voiceAnswerRepository: _VoiceAnswerRepository.success(),
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    await _waitForActiveRecording(tester);
    final cancelCountBeforeExit = recorder.cancelCount;

    await tester.tap(find.byKey(const ValueKey('drawing-back')));
    await tester.pump();
    await tester.pump();

    expect(recorder.cancelCount, greaterThan(cancelCountBeforeExit));
  });

  testWidgets('disposing during recorder start cancels without late notify', (
    tester,
  ) async {
    final recorder = _PendingStartRecorder();
    addTearDown(recorder.completeStart);
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: recorder,
      voiceAnswerRepository: _VoiceAnswerRepository.success(),
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    for (var attempt = 0; attempt < 20 && recorder.startCount == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(recorder.startCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    recorder.completeStart();
    await tester.pump();
    await tester.pump();

    expect(recorder.cancelCount, greaterThan(0));
    expect(recorder.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lifecycle pause invalidates a pending TTS before automatic recording',
    (tester) async {
      final player = _PendingPlayer();
      final recorder = _CountingRecorder();
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await _pumpConversation(
        tester,
        ttsRepository: _TtsRepository(),
        player: player,
        voiceRecorder: recorder,
        voiceAnswerRepository: _VoiceAnswerRepository.success(),
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      player.complete();
      await tester.pump();

      expect(recorder.startCount, 0);
      expect(
        find.byKey(const ValueKey('ai-question-option-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'voice STT consumes the newest queued analysis and resolves the submitted question id',
    (tester) async {
      final detection = _detectionController();
      final conversations = _ConversationRepository();
      final recorder = _CountingRecorder();
      final answers = _CountingAnswerRepository();
      final skips = _PendingSkipRepository();
      final ends = _CountingEndRepository();
      final voiceAnswers = _VoiceAnswerRepository.success(
        result: const VoiceAnswerUploadResult(
          messageId: 9201,
          parentMessageId: 9999,
          sequence: 2,
          speechStatus: 'PROCESSING',
        ),
      );
      final stt = _PendingSttRepository();
      addTearDown(detection.dispose);

      await _pumpConversation(
        tester,
        ttsRepository: _TtsRepository(),
        player: _Player(),
        conversationRepository: conversations,
        voiceRecorder: recorder,
        voiceAnswerRepository: voiceAnswers,
        answerRepository: answers,
        questionSkipRepository: skips,
        endRepository: ends,
        sttResultRepository: stt,
        objectDetectionController: detection,
        startFresh: true,
        voiceNoSpeechTimeout: const Duration(seconds: 30),
      );
      await _detectAnalysis(tester, detection, 701);
      await _detectAnalysis(tester, detection, 702);
      await _detectAnalysis(tester, detection, 703);
      final staleBubbleCallbacks = tester.widget<AiQuestionBubbleOverlay>(
        find.byType(AiQuestionBubbleOverlay),
      );
      await _stopActiveRecording(tester);

      expect(voiceAnswers.questionMessageIds, [9001]);
      expect(stt.messageIds, [9201]);
      expect(
        tester
            .widget<AiQuestionBubbleOverlay>(
              find.byType(AiQuestionBubbleOverlay),
            )
            .visible,
        isFalse,
        reason: '서버가 돌려준 parentMessageId가 아니라 제출 시 캡처한 9001을 해소한다',
      );
      expect(
        find.byKey(const ValueKey('voice-recording-toggle')),
        findsNothing,
      );

      staleBubbleCallbacks.onOptionSelected('1');
      staleBubbleCallbacks.onSkip();
      staleBubbleCallbacks.onEnd();
      await tester.pump();
      expect(answers.calls, 0);
      expect(skips.pending, isNull);
      expect(ends.calls, 0);
      expect(find.textContaining('대화를 그만할까요?'), findsNothing);

      // STT가 아직 진행 중일 때 들어온 탐지도 기존 큐를 최신 값으로 덮어쓴다.
      await _detectAnalysis(tester, detection, 704);
      expect(conversations.analysisIds, [701]);

      stt.completeSuccess(messageId: 9201, text: '가족을 그렸어요');
      await tester.pumpAndSettle();

      expect(conversations.analysisIds, [701, 704]);
      expect(conversations.previousAnswerMessageIds, [null, 9201]);
    },
  );

  testWidgets('voice upload without STT releases the next detection', (
    tester,
  ) async {
    final detection = _detectionController();
    final conversations = _ConversationRepository();
    final voiceAnswers = _VoiceAnswerRepository.success();
    addTearDown(detection.dispose);
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      conversationRepository: conversations,
      voiceRecorder: _CountingRecorder(),
      voiceAnswerRepository: voiceAnswers,
      objectDetectionController: detection,
      startFresh: true,
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );

    await _detectAnalysis(tester, detection, 701);
    await _stopActiveRecording(tester);
    expect(voiceAnswers.questionMessageIds, [9001]);
    expect(
      tester
          .widget<AiQuestionBubbleOverlay>(find.byType(AiQuestionBubbleOverlay))
          .visible,
      isFalse,
    );

    await _detectAnalysis(tester, detection, 702);

    expect(conversations.analysisIds, [701, 702]);
  });

  testWidgets('lifecycle pause invalidates a pending recording stop', (
    tester,
  ) async {
    final recorder = _PendingStopRecorder();
    final voiceAnswers = _VoiceAnswerRepository.success();
    addTearDown(recorder.completeStop);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: recorder,
      voiceAnswerRepository: voiceAnswers,
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    await _waitForActiveRecording(tester);

    await tester.tap(find.byKey(const ValueKey('voice-recording-toggle')));
    await tester.pump();
    expect(recorder.stopCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    recorder.completeStop();
    await tester.pump();
    await tester.pump();
    for (var attempt = 0; attempt < 5; attempt++) {
      final toggle = tester.widget<FilledButton>(
        find.byKey(const ValueKey('voice-recording-toggle')),
      );
      if (toggle.onPressed != null) break;
      await tester.pump();
    }

    expect(recorder.cancelCount, 2);
    expect(voiceAnswers.questionMessageIds, isEmpty);
    expect(find.byKey(const ValueKey('ai-question-option-1')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final recordingController = tester
        .widget<AiQuestionBubbleOverlay>(find.byType(AiQuestionBubbleOverlay))
        .voiceRecordingController!;
    expect(recordingController.status, VoiceRecordingStatus.interrupted);
    expect(recordingController.isBusy, isFalse);
    expect(recordingController.recording, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('voice-recording-toggle')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('voice upload keeps every alternate response single-flight', (
    tester,
  ) async {
    final pendingUpload = Completer<VoiceAnswerUploadResult>();
    final answers = _CountingAnswerRepository();
    final skips = _PendingSkipRepository();
    final ends = _CountingEndRepository();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: _CountingRecorder(),
      voiceAnswerRepository: _VoiceAnswerRepository(pending: pendingUpload),
      answerRepository: answers,
      questionSkipRepository: skips,
      endRepository: ends,
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    await _stopActiveRecording(tester);

    final skip = tester.widget<TextButton>(
      find.byKey(const ValueKey('ai-question-skip')),
    );
    final end = tester.widget<TextButton>(
      find.byKey(const ValueKey('ai-conversation-end')),
    );
    final voice = tester.widget<FilledButton>(
      find.byKey(const ValueKey('voice-recording-toggle')),
    );
    expect(skip.onPressed, isNull);
    expect(end.onPressed, isNull);
    expect(voice.onPressed, isNull);

    // Handler-level guards also reject callbacks captured before the rebuild.
    final bubble = tester.widget<AiQuestionBubbleOverlay>(
      find.byType(AiQuestionBubbleOverlay),
    );
    bubble.onOptionSelected('1');
    bubble.onSkip();
    bubble.onEnd();
    await tester.pump();

    expect(answers.calls, 0);
    expect(skips.pending, isNull);
    expect(ends.calls, 0);
    expect(find.textContaining('대화를 그만할까요?'), findsNothing);
  });

  testWidgets('alternate response blocks a failed voice retry', (tester) async {
    final voiceAnswers = _VoiceAnswerRepository(
      failure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    final skips = _PendingSkipRepository();
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: _CountingRecorder(),
      voiceAnswerRepository: voiceAnswers,
      questionSkipRepository: skips,
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    await _stopActiveRecording(tester);

    final bubble = tester.widget<AiQuestionBubbleOverlay>(
      find.byType(AiQuestionBubbleOverlay),
    );
    final capturedVoiceRetry = bubble.onRetryVoiceAnswerUpload;
    expect(capturedVoiceRetry, isNotNull);
    expect(voiceAnswers.questionMessageIds, [9001]);

    // Both callbacks were captured before the rebuild. The skip must claim the
    // question synchronously, before its first awaited cleanup completes.
    bubble.onSkip();
    capturedVoiceRetry!.call();
    await tester.pump();
    await tester.pump();
    expect(skips.pending, isNotNull);

    final retryFinder = find.byKey(const ValueKey('voice-answer-upload-retry'));
    final retryWasEnabled =
        retryFinder.evaluate().isNotEmpty &&
        tester.widget<TextButton>(retryFinder).onPressed != null;

    expect(
      [retryWasEnabled, voiceAnswers.questionMessageIds.length],
      [false, 1],
    );

    skips.pending!.complete(const QuestionSkipResult(skipped: true));
    await tester.pump();
  });

  testWidgets('voice upload failure keeps the question and reveals options', (
    tester,
  ) async {
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: _CountingRecorder(),
      voiceAnswerRepository: _VoiceAnswerRepository(
        failure: const ApiTransportFailure(
          type: ApiTransportFailureType.connection,
        ),
      ),
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    await _stopActiveRecording(tester);

    expect(
      tester
          .widget<AiQuestionBubbleOverlay>(find.byType(AiQuestionBubbleOverlay))
          .visible,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('voice-answer-upload-failure')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-question-option-1')), findsOneWidget);
  });

  testWidgets('missing voice upload repository keeps selection fallback', (
    tester,
  ) async {
    await _pumpConversation(
      tester,
      ttsRepository: _TtsRepository(),
      player: _Player(),
      voiceRecorder: _CountingRecorder(),
      voiceNoSpeechTimeout: const Duration(seconds: 30),
    );
    await _startManualRecording(tester);
    await _stopActiveRecording(tester);

    expect(
      tester
          .widget<AiQuestionBubbleOverlay>(find.byType(AiQuestionBubbleOverlay))
          .visible,
      isTrue,
    );
    expect(find.byKey(const ValueKey('ai-question-option-1')), findsOneWidget);
  });
}

Future<void> _pumpConversation(
  WidgetTester tester, {
  required QuestionTtsRepository ttsRepository,
  required _Player player,
  VoiceRecorder? voiceRecorder,
  VoiceAnswerRepository? voiceAnswerRepository,
  ConversationAnswerRepository? answerRepository,
  QuestionSkipRepository? questionSkipRepository,
  ConversationEndRepository? endRepository,
  ConversationRepository? conversationRepository,
  SttResultRepository? sttResultRepository,
  DrawingObjectDetectionController? objectDetectionController,
  bool startFresh = false,
  Duration voiceNoSpeechTimeout = const Duration(milliseconds: 100),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '1',
        sessionId: 100,
        conversationRepository:
            conversationRepository ?? _ConversationRepository(),
        conversationAnswerRepository:
            answerRepository ?? const _AnswerRepository(),
        questionSkipRepository:
            questionSkipRepository ?? const _SkipRepository(),
        conversationEndRepository: endRepository ?? const _EndRepository(),
        conversationId: 8001,
        objectDetectionController: objectDetectionController,
        startFresh: startFresh,
        resumeConversation: objectDetectionController == null,
        questionTtsRepository: ttsRepository,
        questionAudioPlayerFactory: () => player,
        voiceRecorder: voiceRecorder ?? _SilentRecorder(),
        voiceAnswerRepository: voiceAnswerRepository,
        sttResultRepository: sttResultRepository,
        microphonePermissionService: const _GrantedMicrophonePermission(),
        voiceNoSpeechTimeout: voiceNoSpeechTimeout,
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

Future<void> _startManualRecording(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('voice-recording-toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pump();
  await _waitForActiveRecording(tester);
}

Future<void> _stopActiveRecording(WidgetTester tester) async {
  await _waitForActiveRecording(tester);
  final toggle = find.byKey(const ValueKey('voice-recording-toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pump();
  await tester.pump();
}

Future<void> _waitForActiveRecording(WidgetTester tester) async {
  final recordingLabel = find.textContaining('녹음 끝내기');
  for (
    var attempt = 0;
    attempt < 20 && recordingLabel.evaluate().isEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(recordingLabel, findsOneWidget);
}

Future<void> _detectAnalysis(
  WidgetTester tester,
  DrawingObjectDetectionController detection,
  int analysisId,
) async {
  _nextAnalysisId = analysisId;
  detection
    ..onDrawingInputStarted()
    ..onDrawingInputEnded();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

int _nextAnalysisId = 701;

DrawingObjectDetectionController _detectionController() =>
    DrawingObjectDetectionController(
      saveDraft: () async => DraftSaveResponseDto(
        drawingAssetId: _nextAnalysisId,
        assetVersion: 1,
        lastEventSequence: 1,
        savedAt: '2026-08-03T00:00:00Z',
        expiresAt: '2026-08-04T00:00:00Z',
      ),
      requestDetection: (_) async => ObjectDetectionResponseDto(
        drawingAnalysisId: _nextAnalysisId,
        drawingSessionId: 100,
        drawingAssetId: _nextAnalysisId,
        requestId: 'req-$_nextAnalysisId',
        analysisType: 'OBJECT_DETECTION',
        status: 'SUCCEEDED',
        model: const DrawingAnalysisModelDto(name: 'yolo', version: '1'),
        detections: const [],
        requestedAt: '2026-08-03T00:00:00Z',
        processedAt: '2026-08-03T00:00:01Z',
      ),
      debounceDuration: const Duration(seconds: 3),
    );

final class _AnswerRepository implements ConversationAnswerRepository {
  const _AnswerRepository();

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async => const OptionAnswerResult(answerMessageId: 9101);
}

final class _CountingAnswerRepository implements ConversationAnswerRepository {
  int calls = 0;

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    calls += 1;
    return const OptionAnswerResult(answerMessageId: 9101);
  }
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

final class _CountingEndRepository implements ConversationEndRepository {
  int calls = 0;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    calls += 1;
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: 'CHILD_REQUEST',
      completedAt: '2026-08-03T00:00:00Z',
      nextStage: 'REFLECTION',
    );
  }
}

final class _ConversationRepository implements ConversationRepository {
  final List<int?> analysisIds = [];
  final List<int?> previousAnswerMessageIds = [];
  int _nextQuestionMessageId = 9001;

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
  }) async {
    analysisIds.add(request.basisAnalysisId);
    previousAnswerMessageIds.add(request.previousAnswerMessageId);
    return AiQuestion(
      messageId: _nextQuestionMessageId++,
      conversationId: conversationId,
      sequence: analysisIds.length,
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

class _Player implements QuestionAudioPlayer {
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

final class _PendingPlayer extends _Player {
  final Completer<void> _play = Completer<void>();

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) {
    playCount += 1;
    return _play.future;
  }

  void complete() => _play.complete();
}

final class _CountingRecorder extends _SilentRecorder {
  int startCount = 0;
  int cancelCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }
}

final class _PendingStartRecorder extends _CountingRecorder {
  final Completer<void> _start = Completer<void>();
  int disposeCount = 0;

  @override
  Future<void> start() {
    startCount += 1;
    return _start.future;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  void completeStart() {
    if (!_start.isCompleted) _start.complete();
  }
}

final class _PendingStopRecorder extends _CountingRecorder {
  final Completer<String?> _stop = Completer<String?>();
  int stopCount = 0;

  @override
  Future<String?> stop() {
    stopCount += 1;
    return _stop.future;
  }

  void completeStop() {
    if (!_stop.isCompleted) _stop.complete('/tmp/voice-answer.m4a');
  }
}

final class _PendingSkipRepository implements QuestionSkipRepository {
  Completer<QuestionSkipResult>? pending;

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) {
    return (pending ??= Completer<QuestionSkipResult>()).future;
  }
}

final class _VoiceAnswerRepository implements VoiceAnswerRepository {
  _VoiceAnswerRepository({this.result, this.failure, this.pending});

  factory _VoiceAnswerRepository.success({VoiceAnswerUploadResult? result}) =>
      _VoiceAnswerRepository(
        result:
            result ??
            const VoiceAnswerUploadResult(
              messageId: 9201,
              parentMessageId: 9001,
              sequence: 2,
              speechStatus: 'PROCESSING',
            ),
      );

  final VoiceAnswerUploadResult? result;
  final Object? failure;
  final Completer<VoiceAnswerUploadResult>? pending;
  final List<int> questionMessageIds = [];

  @override
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  }) async {
    questionMessageIds.add(request.questionMessageId);
    if (failure case final caught?) throw caught;
    if (pending case final completer?) return completer.future;
    return result!;
  }
}

final class _PendingSttRepository implements SttResultRepository {
  final Completer<SttResult> _result = Completer<SttResult>();
  final List<int> messageIds = [];

  @override
  Future<SttResult> getResult({
    required int conversationId,
    required int messageId,
    required int afterSequence,
  }) {
    messageIds.add(messageId);
    return _result.future;
  }

  void completeSuccess({required int messageId, required String text}) {
    _result.complete(
      SttResult(
        messageId: messageId,
        status: SttSpeechStatus.success,
        text: text,
      ),
    );
  }
}

class _SilentRecorder implements VoiceRecorder {
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
