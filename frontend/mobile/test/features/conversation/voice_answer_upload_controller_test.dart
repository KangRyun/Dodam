import 'dart:async';
import 'dart:io';

import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
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
}

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
  _FakeVoiceAnswerRepository({this.failOnce = false, this.result});

  final bool failOnce;
  final Future<VoiceAnswerUploadResult>? result;
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
    if (failOnce && callCount == 1) throw Exception('temporary failure');
    return result ?? _result;
  }
}
