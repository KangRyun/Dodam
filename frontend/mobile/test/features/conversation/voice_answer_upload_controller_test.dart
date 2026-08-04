import 'dart:async';
import 'dart:io';

import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_error.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('음성 파일과 metadata를 백엔드 multipart 계약으로 전송한다', () async {
    final directory = await Directory.systemTemp.createTemp('dodam-voice-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/answer.m4a');
    await file.writeAsBytes([1, 2, 3]);
    final interceptor = _VoiceUploadInterceptor();
    final repository = RemoteVoiceAnswerRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final result = await repository.upload(
      conversationId: 20,
      request: VoiceAnswerUploadRequest(
        questionMessageId: 10,
        recording: VoiceRecording(
          filePath: file.path,
          duration: const Duration(seconds: 4),
          startedAt: DateTime.parse('2026-07-24T01:00:00Z'),
          endedAt: DateTime.parse('2026-07-24T01:00:04Z'),
          completionReason: VoiceRecordingCompletionReason.silence,
        ),
      ),
      idempotencyKey: 'voice-answer-key',
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/conversations/20/answers/voice');
    expect(request.headers['Idempotency-Key'], 'voice-answer-key');
    final form = request.data as FormData;
    expect(form.files.single.key, 'audio');
    expect(form.fields.single.key, 'metadata');
    expect(form.fields.single.value, contains('"questionMessageId":10'));
    expect(form.fields.single.value, contains('"stopReason":"SILENCE"'));
    expect(result.speechStatus, 'PENDING');
  });

  test('실패한 음성 업로드는 같은 멱등성 키와 파일로 재시도한다', () async {
    final repository = _FakeVoiceAnswerRepository(failOnce: true);
    final controller = VoiceAnswerUploadController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );
    addTearDown(controller.dispose);
    final recording = VoiceRecording(
      filePath: '/tmp/answer.m4a',
      duration: const Duration(seconds: 3),
      startedAt: DateTime.parse('2026-07-24T01:00:00Z'),
      endedAt: DateTime.parse('2026-07-24T01:00:03Z'),
    );

    expect(
      await controller.submit(questionMessageId: 10, recording: recording),
      isFalse,
    );
    expect(controller.status, VoiceAnswerUploadStatus.failure);
    expect(await controller.retry(), isTrue);
    expect(repository.keys, ['stable-key', 'stable-key']);
    expect(repository.requests[0], same(repository.requests[1]));
  });

  test('다른 응답이 시작되면 실패한 음성 재시도를 폐기한다', () async {
    final repository = _FakeVoiceAnswerRepository(failOnce: true);
    final controller = VoiceAnswerUploadController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'abandoned-key',
    );
    addTearDown(controller.dispose);

    expect(
      await controller.submit(questionMessageId: 10, recording: _recording),
      isFalse,
    );
    expect(controller.canRetry, isTrue);

    controller.abandonPendingAnswer();

    expect(controller.status, VoiceAnswerUploadStatus.idle);
    expect(controller.canRetry, isFalse);
    expect(await controller.retry(), isFalse);
    expect(repository.callCount, 1);
  });

  test('음성 처리 동의가 없으면 재시도하지 않고 동의 필요 상태로 알린다', () async {
    final repository = _FakeVoiceAnswerRepository(
      error: const ApiResponseFailure(
        statusCode: 403,
        error: ApiError(
          code: 'VOICE_CONSENT_REQUIRED',
          message: '음성 처리 동의가 필요합니다.',
        ),
      ),
    );
    final controller = VoiceAnswerUploadController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'consent-key',
    );
    addTearDown(controller.dispose);

    expect(
      await controller.submit(questionMessageId: 10, recording: _recording),
      isFalse,
    );
    expect(controller.status, VoiceAnswerUploadStatus.consentRequired);
    // 재전송해도 동의가 생기지 않으므로 보류 요청을 남기지 않는다.
    expect(await controller.retry(), isFalse);
    expect(repository.callCount, 1);
  });

  test('동의 외 403은 일반 실패로 두어 재시도를 허용한다', () async {
    final repository = _FakeVoiceAnswerRepository(
      error: const ApiResponseFailure(
        statusCode: 403,
        error: ApiError(
          code: 'CONVERSATION_ACCESS_DENIED',
          message: '접근 권한이 없습니다.',
        ),
      ),
    );
    final controller = VoiceAnswerUploadController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'denied-key',
    );
    addTearDown(controller.dispose);

    expect(
      await controller.submit(questionMessageId: 10, recording: _recording),
      isFalse,
    );
    expect(controller.status, VoiceAnswerUploadStatus.failure);
  });

  test('전송 중 중복 업로드를 차단한다', () async {
    final completer = Completer<VoiceAnswerUploadResult>();
    final repository = _FakeVoiceAnswerRepository(result: completer.future);
    final controller = VoiceAnswerUploadController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'upload-key',
    );
    addTearDown(controller.dispose);
    final recording = VoiceRecording(
      filePath: '/tmp/answer.m4a',
      duration: const Duration(seconds: 3),
      startedAt: DateTime.parse('2026-07-24T01:00:00Z'),
      endedAt: DateTime.parse('2026-07-24T01:00:03Z'),
    );

    final first = controller.submit(
      questionMessageId: 10,
      recording: recording,
    );
    expect(
      await controller.submit(questionMessageId: 10, recording: recording),
      isFalse,
    );
    completer.complete(_result);
    expect(await first, isTrue);
    expect(repository.callCount, 1);
  });

  test('dispose 뒤 늦게 도착한 업로드 응답은 상태를 바꾸지 않는다', () async {
    final completer = Completer<VoiceAnswerUploadResult>();
    final controller = VoiceAnswerUploadController(
      _FakeVoiceAnswerRepository(result: completer.future),
      conversationId: 20,
      idempotencyKeyProvider: () => 'voice-key',
    );

    final pending = controller.submit(
      questionMessageId: 10,
      recording: _recording,
    );
    controller.dispose();
    completer.complete(_result);

    expect(await pending, isFalse);
    expect(controller.status, VoiceAnswerUploadStatus.uploading);
    expect(controller.result, isNull);
  });

  test('dispose 뒤에는 재전송하지 않는다', () async {
    final repository = _FakeVoiceAnswerRepository(failOnce: true);
    final controller = VoiceAnswerUploadController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'voice-key',
    );

    expect(
      await controller.submit(questionMessageId: 10, recording: _recording),
      isFalse,
    );
    controller.dispose();

    expect(await controller.retry(), isFalse);
    expect(repository.callCount, 1);
  });
}

final _recording = VoiceRecording(
  filePath: '/tmp/answer.m4a',
  duration: const Duration(seconds: 3),
  startedAt: DateTime.parse('2026-07-24T01:00:00Z'),
  endedAt: DateTime.parse('2026-07-24T01:00:03Z'),
);

const _result = VoiceAnswerUploadResult(
  messageId: 30,
  parentMessageId: 10,
  sequence: 3,
  speechStatus: 'PENDING',
);

final class _VoiceUploadInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 201,
        data: const {
          'messageId': 30,
          'parentMessageId': 10,
          'sequence': 3,
          'senderType': 'CHILD',
          'messageType': 'VOICE_ANSWER',
          'rawText': null,
          'sttText': null,
          'speechStatus': 'PENDING',
          'sttConfidence': null,
          'needsGuardianConfirmation': false,
          'createdAt': '2026-07-24T01:00:04',
        },
      ),
    );
  }
}

final class _FakeVoiceAnswerRepository implements VoiceAnswerRepository {
  _FakeVoiceAnswerRepository({this.failOnce = false, this.result, this.error});

  final bool failOnce;
  final Future<VoiceAnswerUploadResult>? result;
  final Object? error;
  int callCount = 0;
  final List<String> keys = [];
  final List<VoiceAnswerUploadRequest> requests = [];

  @override
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  }) async {
    callCount++;
    keys.add(idempotencyKey);
    requests.add(request);
    if (error != null) throw error!;
    if (failOnce && callCount == 1) throw Exception('temporary failure');
    return result ?? _result;
  }
}
