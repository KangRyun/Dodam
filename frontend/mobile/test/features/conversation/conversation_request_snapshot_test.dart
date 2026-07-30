import 'dart:async';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 대화 쓰기 요청의 Idempotency-Key와 Body가 한 snapshot으로 움직이는지 고정한다.
///
/// 백엔드는 Key와 Body fingerprint를 함께 저장하고 불일치 시
/// `IDEMPOTENCY_KEY_REUSED`(409)로 거절한다. Key만 재사용하고 Body를 바꾸면
/// 요청이 통째로 거절되고, 반대로 매번 새 Key를 쓰면 응답이 유실된 성공 요청이
/// 중복 저장된다.
void main() {
  group('선택형 답변 snapshot', () {
    test('같은 답변 재시도는 같은 Key와 같은 Body를 보낸다', () async {
      final repository = _AnswerRepository(failure: _failure(503));
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      repository.failure = null;
      await controller.submit(questionMessageId: 10, option: _option('1'));

      expect(repository.keys, hasLength(2));
      expect(repository.keys.toSet(), hasLength(1));
      expect(repository.bodies.toSet(), hasLength(1));
      expect(controller.status, OptionAnswerSubmissionStatus.success);
    });

    // 서버가 저장했을 수 있는 실패에서 다른 답변을 새 Key로 보내면 답변이 두 번 남는다.
    for (final (name, failure) in <(String, Object)>[
      ('timeout', _transport(ApiTransportFailureType.receiveTimeout)),
      ('connection', _transport(ApiTransportFailureType.connection)),
      ('5xx', _failure(500)),
    ]) {
      test('$name 실패 뒤 다른 선택은 전송하지 않는다', () async {
        final repository = _AnswerRepository(failure: failure);
        final controller = _answerController(repository);

        await controller.submit(questionMessageId: 10, option: _option('1'));
        final blocked = await controller.submit(
          questionMessageId: 10,
          option: _option('2'),
        );

        expect(blocked, isFalse);
        expect(repository.keys, hasLength(1));
        expect(controller.isLockedToPendingAnswer, isTrue);
        expect(controller.pendingOptionId, '1');
      });

      test('$name 실패 뒤 같은 선택 재시도는 그대로 허용한다', () async {
        final repository = _AnswerRepository(failure: failure);
        final controller = _answerController(repository);

        await controller.submit(questionMessageId: 10, option: _option('1'));
        repository.failure = null;
        final retried = await controller.submit(
          questionMessageId: 10,
          option: _option('1'),
        );

        expect(retried, isTrue);
        expect(repository.keys.toSet(), hasLength(1));
      });
    }

    test('400 확정 실패 뒤 다른 선택은 새 Key와 Body로 보낸다', () async {
      final repository = _AnswerRepository(failure: _failure(400));
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      expect(controller.isLockedToPendingAnswer, isFalse);
      repository.failure = null;
      final sent = await controller.submit(
        questionMessageId: 10,
        option: _option('2'),
      );

      expect(sent, isTrue);
      expect(repository.keys.toSet(), hasLength(2));
      expect(repository.bodies.toSet(), hasLength(2));
    });

    for (final status in [401, 403, 404, 422]) {
      test('$status 확정 실패는 Controller 직접 재제출도 차단한다', () async {
        final repository = _AnswerRepository(failure: _failure(status));
        final controller = _answerController(repository);

        await controller.submit(questionMessageId: 10, option: _option('1'));
        expect(controller.isLockedToPendingAnswer, isFalse);
        repository.failure = null;
        final sent = await controller.submit(
          questionMessageId: 10,
          option: _option('2'),
        );

        expect(sent, isFalse);
        expect(repository.keys, hasLength(1));
      });
    }

    test('질문이 바뀌면 새 snapshot과 새 Key를 쓴다', () async {
      final repository = _AnswerRepository(failure: _failure(503));
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      controller.beginQuestion(11);
      repository.failure = null;
      await controller.submit(questionMessageId: 11, option: _option('1'));

      expect(repository.keys.toSet(), hasLength(2));
      expect(controller.isLockedToPendingAnswer, isFalse);
    });

    test('선택지가 달라지면 Body와 Key가 함께 달라진다', () async {
      final repository = _AnswerRepository();
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      controller.beginQuestion(10);
      await controller.submit(questionMessageId: 10, option: _option('2'));

      expect(repository.keys.toSet(), hasLength(2));
      expect(repository.bodies.toSet(), hasLength(2));
    });

    test('전송 중 연속 탭은 API를 한 번만 호출한다', () async {
      final completer = Completer<OptionAnswerResult>();
      final repository = _AnswerRepository(pending: completer.future);
      final controller = _answerController(repository);

      final first = controller.submit(
        questionMessageId: 10,
        option: _option('1'),
      );
      final second = await controller.submit(
        questionMessageId: 10,
        option: _option('1'),
      );
      final third = await controller.submit(
        questionMessageId: 10,
        option: _option('2'),
      );

      expect(second, isFalse);
      expect(third, isFalse);
      expect(repository.keys, hasLength(1));
      completer.complete(const OptionAnswerResult(answerMessageId: 30));
      expect(await first, isTrue);
    });

    test('재시도 가능 여부는 공통 실패 분류를 따른다', () async {
      final retryable = _answerController(
        _AnswerRepository(failure: _failure(503)),
      );
      await retryable.submit(questionMessageId: 10, option: _option('1'));
      expect(retryable.canRetry, isTrue);

      final permanent = _answerController(
        _AnswerRepository(failure: _failure(403)),
      );
      await permanent.submit(questionMessageId: 10, option: _option('1'));
      expect(permanent.canRetry, isFalse);
    });

    test('OPTION_ANSWER_STORAGE_CONFLICT는 저장된 409라 재시도하지 않는다', () async {
      final repository = _AnswerRepository(
        failure: _failure(409, 'OPTION_ANSWER_STORAGE_CONFLICT'),
      );
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      expect(controller.canRetry, isFalse);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      expect(repository.keys, hasLength(1));
      expect(controller.status, OptionAnswerSubmissionStatus.failure);
    });

    test('cancelled 뒤 같은 답변은 같은 Key와 Body snapshot을 쓴다', () async {
      final repository = _AnswerRepository(
        failure: _transport(ApiTransportFailureType.cancelled),
      );
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      expect(controller.canRetry, isFalse);
      expect(controller.isLockedToPendingAnswer, isTrue);

      repository.failure = null;
      await controller.submit(questionMessageId: 10, option: _option('1'));

      expect(repository.keys.toSet(), hasLength(1));
      expect(repository.bodies.toSet(), hasLength(1));
    });
  });

  group('선택형 답변 stale 응답', () {
    test('이전 질문의 늦은 성공은 새 질문 상태를 덮지 않는다', () async {
      final completer = Completer<OptionAnswerResult>();
      final repository = _AnswerRepository(pending: completer.future);
      final controller = _answerController(repository);

      final stale = controller.submit(
        questionMessageId: 10,
        option: _option('1'),
      );
      controller.beginQuestion(11);
      completer.complete(const OptionAnswerResult(answerMessageId: 30));

      expect(await stale, isFalse);
      expect(controller.status, OptionAnswerSubmissionStatus.idle);
      expect(controller.answerMessageId, isNull);
      expect(controller.selectedOptionId, isNull);
    });

    test('이전 질문의 늦은 실패도 새 질문 상태를 덮지 않는다', () async {
      final completer = Completer<OptionAnswerResult>();
      final repository = _AnswerRepository(pending: completer.future);
      final controller = _answerController(repository);

      final stale = controller.submit(
        questionMessageId: 10,
        option: _option('1'),
      );
      controller.beginQuestion(11);
      completer.completeError(_failure(500));

      expect(await stale, isFalse);
      expect(controller.status, OptionAnswerSubmissionStatus.idle);
      expect(controller.error, isNull);
    });

    test('같은 질문의 정상 재시도는 stale로 오판하지 않는다', () async {
      final repository = _AnswerRepository(failure: _failure(503));
      final controller = _answerController(repository);

      await controller.submit(questionMessageId: 10, option: _option('1'));
      repository.failure = null;
      final retried = await controller.submit(
        questionMessageId: 10,
        option: _option('1'),
      );

      expect(retried, isTrue);
      expect(controller.status, OptionAnswerSubmissionStatus.success);
    });
  });

  group('건너뛰기 stale 응답과 Key', () {
    test('이전 질문의 늦은 성공·실패를 무시한다', () async {
      for (final complete in [true, false]) {
        final completer = Completer<QuestionSkipResult>();
        final controller = QuestionSkipController(
          _SkipRepository(pending: completer.future),
          conversationId: 20,
          idempotencyKeyProvider: _sequentialKeys(),
        );

        final stale = controller.submit(questionMessageId: 10);
        controller.beginQuestion(11);
        if (complete) {
          completer.complete(const QuestionSkipResult(skipped: true));
        } else {
          completer.completeError(_failure(500));
        }

        expect(await stale, isFalse);
        expect(controller.status, QuestionSkipStatus.idle);
      }
    });

    test('질문이 바뀌면 새 Key를 쓴다', () async {
      final repository = _SkipRepository(failure: _failure(503));
      final controller = QuestionSkipController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10);
      controller.beginQuestion(11);
      repository.failure = null;
      await controller.submit(questionMessageId: 11);

      expect(repository.keys.toSet(), hasLength(2));
    });

    test('같은 질문 재시도는 같은 Key를 쓰고 확정 실패는 재시도를 막는다', () async {
      final retryable = _SkipRepository(failure: _failure(503));
      final controller = QuestionSkipController(
        retryable,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      await controller.submit(questionMessageId: 10);
      expect(controller.canRetry, isTrue);
      retryable.failure = null;
      await controller.submit(questionMessageId: 10);
      expect(retryable.keys.toSet(), hasLength(1));

      final permanent = QuestionSkipController(
        _SkipRepository(failure: _failure(403)),
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      await permanent.submit(questionMessageId: 10);
      expect(permanent.canRetry, isFalse);
    });

    test('401은 Controller 직접 재제출도 차단한다', () async {
      final repository = _SkipRepository(failure: _failure(401));
      final controller = QuestionSkipController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10);
      repository.failure = null;
      expect(await controller.submit(questionMessageId: 10), isFalse);
      expect(repository.keys, hasLength(1));
    });

    test('cancelled 뒤 같은 동작은 같은 Key를 쓴다', () async {
      final repository = _SkipRepository(
        failure: _transport(ApiTransportFailureType.cancelled),
      );
      final controller = QuestionSkipController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10);
      expect(controller.canRetry, isFalse);
      repository.failure = null;
      await controller.submit(questionMessageId: 10);

      expect(repository.keys, hasLength(2));
      expect(repository.keys.toSet(), hasLength(1));
    });
  });

  group('음성 답변 stale 응답과 Key', () {
    test('이전 질문의 늦은 성공·실패를 무시한다', () async {
      for (final complete in [true, false]) {
        final completer = Completer<VoiceAnswerUploadResult>();
        final controller = VoiceAnswerUploadController(
          _VoiceRepository(pending: completer.future),
          conversationId: 20,
          idempotencyKeyProvider: _sequentialKeys(),
        );

        final stale = controller.submit(
          questionMessageId: 10,
          recording: _recording,
        );
        controller.beginQuestion(11);
        if (complete) {
          completer.complete(_uploadResult);
        } else {
          completer.completeError(_failure(500));
        }

        expect(await stale, isFalse);
        expect(controller.status, VoiceAnswerUploadStatus.idle);
        expect(controller.result, isNull);
      }
    });

    test('질문이 바뀌면 보류 파일과 Key를 버린다', () async {
      final repository = _VoiceRepository(failure: _failure(503));
      final controller = VoiceAnswerUploadController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10, recording: _recording);
      controller.beginQuestion(11);

      expect(await controller.retry(), isFalse);
      expect(repository.keys, hasLength(1));
    });

    test('같은 질문 재전송은 같은 Key와 같은 파일을 쓴다', () async {
      final repository = _VoiceRepository(failure: _failure(503));
      final controller = VoiceAnswerUploadController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10, recording: _recording);
      expect(controller.canRetry, isTrue);
      repository.failure = null;
      expect(await controller.retry(), isTrue);

      expect(repository.keys.toSet(), hasLength(1));
      expect(repository.requests.map((r) => r.recording.filePath).toSet(), {
        _recording.filePath,
      });
    });

    test('확정 실패는 재시도를 제공하지 않는다', () async {
      for (final status in [401, 403, 404, 422]) {
        final controller = VoiceAnswerUploadController(
          _VoiceRepository(failure: _failure(status)),
          conversationId: 20,
          idempotencyKeyProvider: _sequentialKeys(),
        );

        await controller.submit(questionMessageId: 10, recording: _recording);

        expect(controller.canRetry, isFalse, reason: 'status=$status');
        expect(await controller.retry(), isFalse);
      }
    });

    test('401은 새 녹음으로 Controller를 직접 호출해도 차단한다', () async {
      final repository = _VoiceRepository(failure: _failure(401));
      final controller = VoiceAnswerUploadController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10, recording: _recording);
      repository.failure = null;
      expect(
        await controller.submit(questionMessageId: 10, recording: _recording),
        isFalse,
      );
      expect(repository.keys, hasLength(1));
    });

    test('음성 동의 필요는 전용 상태를 유지한다', () async {
      final controller = VoiceAnswerUploadController(
        _VoiceRepository(failure: _failure(403, 'VOICE_CONSENT_REQUIRED')),
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10, recording: _recording);

      expect(controller.status, VoiceAnswerUploadStatus.consentRequired);
      expect(controller.canRetry, isFalse);
    });

    test('VOICE_ANSWER_IN_PROGRESS만 Voice에서 같은 snapshot 재시도를 허용한다', () async {
      final repository = _VoiceRepository(
        failure: _failure(409, 'VOICE_ANSWER_IN_PROGRESS'),
      );
      final controller = VoiceAnswerUploadController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10, recording: _recording);
      expect(controller.canRetry, isTrue);
      repository.failure = null;
      expect(await controller.retry(), isTrue);

      expect(repository.keys.toSet(), hasLength(1));
      expect(repository.requests.map((request) => request.recording).toSet(), {
        _recording,
      });
    });

    test('cancelled 뒤 retry는 같은 Key와 파일 snapshot을 쓴다', () async {
      final repository = _VoiceRepository(
        failure: _transport(ApiTransportFailureType.cancelled),
      );
      final controller = VoiceAnswerUploadController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(questionMessageId: 10, recording: _recording);
      expect(controller.canRetry, isFalse);
      repository.failure = null;
      expect(await controller.retry(), isTrue);

      expect(repository.keys.toSet(), hasLength(1));
      expect(repository.requests.map((request) => request.recording).toSet(), {
        _recording,
      });
    });
  });

  group('대화 종료 재시도 분류', () {
    test('5xx는 같은 Key·Body로 재시도할 수 있다', () async {
      final repository = _EndRepository(failure: _failure(500));
      final controller = ConversationEndController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(lastQuestionMessageId: 10);
      expect(controller.canRetry, isTrue);
      repository.failure = null;
      await controller.submit(lastQuestionMessageId: 10);

      expect(repository.keys.toSet(), hasLength(1));
      expect(controller.completed, isTrue);
    });

    test('처리 충돌 409도 재시도를 허용한다', () async {
      final controller = ConversationEndController(
        _EndRepository(failure: _failure(409, 'CONVERSATION_END_CONFLICT')),
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(lastQuestionMessageId: 10);

      expect(controller.canRetry, isTrue);
    });

    for (final status in [401, 403, 404, 422]) {
      test('$status 확정 실패에는 재시도를 제공하지 않는다', () async {
        final controller = ConversationEndController(
          _EndRepository(failure: _failure(status)),
          conversationId: 20,
          idempotencyKeyProvider: _sequentialKeys(),
        );

        await controller.submit(lastQuestionMessageId: 10);

        expect(controller.canRetry, isFalse);
      });
    }

    test('401은 Controller 직접 종료 재제출도 차단한다', () async {
      final repository = _EndRepository(failure: _failure(401));
      final controller = ConversationEndController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(lastQuestionMessageId: 10);
      repository.failure = null;
      expect(await controller.submit(lastQuestionMessageId: 10), isFalse);
      expect(repository.keys, hasLength(1));
      expect(controller.requestSnapshot, isNull);
    });

    test('cancelled 뒤 같은 종료는 같은 Key와 Body snapshot을 쓴다', () async {
      final repository = _EndRepository(
        failure: _transport(ApiTransportFailureType.cancelled),
      );
      final controller = ConversationEndController(
        repository,
        conversationId: 20,
        idempotencyKeyProvider: _sequentialKeys(),
      );

      await controller.submit(lastQuestionMessageId: 10);
      final firstRequest = controller.requestSnapshot;
      expect(controller.canRetry, isFalse);
      repository.failure = null;
      await controller.submit(lastQuestionMessageId: 999);

      expect(repository.keys.toSet(), hasLength(1));
      expect(controller.requestSnapshot, same(firstRequest));
      expect(controller.requestSnapshot?.lastQuestionMessageId, 10);
      expect(repository.requests, everyElement(same(firstRequest)));
    });
  });

  group('재시도 분류 정책', () {
    test('endpoint별 처리 중 전용 wire code만 재시도 가능하게 다룬다', () {
      expect(
        isProcessingConflict(
          _failure(409, 'VOICE_ANSWER_IN_PROGRESS'),
          endpoint: ConversationRequestEndpoint.voiceAnswer,
        ),
        isTrue,
      );
      expect(
        isProcessingConflict(
          _failure(409, 'VOICE_ANSWER_IN_PROGRESS'),
          endpoint: ConversationRequestEndpoint.optionAnswer,
        ),
        isFalse,
      );
      // 상태가 바뀌지 않는 409는 재시도 대상이 아니다.
      expect(
        isProcessingConflict(
          _failure(409, 'QUESTION_STORAGE_CONFLICT'),
          endpoint: ConversationRequestEndpoint.nextQuestion,
        ),
        isFalse,
      );
      expect(
        isProcessingConflict(
          _failure(409, 'CONVERSATION_409_002'),
          endpoint: ConversationRequestEndpoint.nextQuestion,
        ),
        isFalse,
      );
      expect(
        canRetryConversationRequest(
          _failure(409, 'CONVERSATION_END_CONFLICT'),
          endpoint: ConversationRequestEndpoint.conversationEnd,
        ),
        isTrue,
      );
      expect(
        canRetryConversationRequest(
          _failure(409, 'QUESTION_SKIP_CONFLICT'),
          endpoint: ConversationRequestEndpoint.questionSkip,
        ),
        isTrue,
      );
      expect(
        canRetryConversationRequest(
          _failure(409, 'OPTION_ANSWER_STORAGE_CONFLICT'),
          endpoint: ConversationRequestEndpoint.optionAnswer,
        ),
        isFalse,
      );
    });

    test('모호한 next-question 409는 재시도하지 않지만 snapshot은 보존한다', () {
      final failure = _failure(409, 'CONVERSATION_409_002');

      expect(
        canRetryConversationRequest(
          failure,
          endpoint: ConversationRequestEndpoint.nextQuestion,
        ),
        isFalse,
      );
      expect(
        shouldKeepRequestSnapshot(
          failure,
          endpoint: ConversationRequestEndpoint.nextQuestion,
        ),
        isTrue,
      );
    });

    test('cancelled는 UI 재시도 불가여도 모든 endpoint에서 snapshot을 보존한다', () {
      final failure = _transport(ApiTransportFailureType.cancelled);

      for (final endpoint in ConversationRequestEndpoint.values) {
        expect(
          canRetryConversationRequest(failure, endpoint: endpoint),
          isFalse,
          reason: endpoint.name,
        );
        expect(
          shouldKeepRequestSnapshot(failure, endpoint: endpoint),
          isTrue,
          reason: endpoint.name,
        );
      }
    });

    test('불확실 판정은 공통 ApiFailurePresentation과 일치한다', () {
      expect(
        isOutcomeUncertain(_transport(ApiTransportFailureType.connection)),
        isTrue,
      );
      expect(isOutcomeUncertain(_failure(500)), isTrue);
      expect(isOutcomeUncertain(Exception('알 수 없음')), isTrue);
      expect(isOutcomeUncertain(_failure(403)), isFalse);
      expect(isOutcomeUncertain(_failure(422)), isFalse);
    });
  });
}

// ---------------------------------------------------------------- helpers

OptionAnswerSubmissionController _answerController(
  _AnswerRepository repository,
) => OptionAnswerSubmissionController(
  repository,
  conversationId: 20,
  idempotencyKeyProvider: _sequentialKeys(),
);

/// 호출마다 다른 Key를 준다 — 재사용은 Controller가 보장해야 한다.
String Function() _sequentialKeys() {
  var next = 0;
  return () => 'key-${next++}';
}

AiQuestionOption _option(String id) => AiQuestionOption(
  optionId: id,
  type: 'EMOJI',
  label: '라벨$id',
  value: 'V$id',
);

ApiResponseFailure _failure(int statusCode, [String? code]) =>
    ApiResponseFailure(
      statusCode: statusCode,
      error: code == null ? null : ApiError(code: code, message: '실패'),
    );

ApiTransportFailure _transport(ApiTransportFailureType type) =>
    ApiTransportFailure(type: type);

final _recording = VoiceRecording(
  filePath: '/tmp/answer.m4a',
  duration: const Duration(seconds: 3),
  startedAt: DateTime.parse('2026-07-30T01:00:00Z'),
  endedAt: DateTime.parse('2026-07-30T01:00:03Z'),
);

const _uploadResult = VoiceAnswerUploadResult(
  messageId: 30,
  parentMessageId: 10,
  sequence: 3,
  speechStatus: 'PENDING',
);

// ------------------------------------------------------------------ fakes

final class _AnswerRepository implements ConversationAnswerRepository {
  _AnswerRepository({this.failure, this.pending});

  Object? failure;
  Future<OptionAnswerResult>? pending;
  final List<String> keys = [];
  final List<String> bodies = [];

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    bodies.add(request.toJson().toString());
    if (failure case final caught?) throw caught;
    return pending == null
        ? const OptionAnswerResult(answerMessageId: 30)
        : await pending!;
  }
}

final class _SkipRepository implements QuestionSkipRepository {
  _SkipRepository({this.failure, this.pending});

  Object? failure;
  Future<QuestionSkipResult>? pending;
  final List<String> keys = [];

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    if (failure case final caught?) throw caught;
    return pending == null
        ? const QuestionSkipResult(skipped: true)
        : await pending!;
  }
}

final class _VoiceRepository implements VoiceAnswerRepository {
  _VoiceRepository({this.failure, this.pending});

  Object? failure;
  Future<VoiceAnswerUploadResult>? pending;
  final List<String> keys = [];
  final List<VoiceAnswerUploadRequest> requests = [];

  @override
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    requests.add(request);
    if (failure case final caught?) throw caught;
    return pending == null ? _uploadResult : await pending!;
  }
}

final class _EndRepository implements ConversationEndRepository {
  _EndRepository({this.failure});

  Object? failure;
  final List<String> keys = [];
  final List<ConversationEndRequest> requests = [];

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    requests.add(request);
    if (failure case final caught?) throw caught;
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: 'CHILD_REQUEST',
      completedAt: '2026-07-30T00:00:00Z',
      nextStage: 'REFLECTION',
    );
  }
}
