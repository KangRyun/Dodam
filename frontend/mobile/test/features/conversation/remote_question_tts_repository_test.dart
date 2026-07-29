import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TTS 응답의 nullable 메타데이터를 계약대로 파싱한다', () {
    final cacheHit = QuestionTtsResponse.fromJson({
      'audioUrl': '/api/v1/conversation-messages/803/audio',
      'expiresAt': null,
      'durationMs': null,
      'subtitle': '질문',
    });
    final newlyCreated = QuestionTtsResponse.fromJson({
      'audioUrl': '/api/v1/conversation-messages/803/audio',
      'expiresAt': null,
      'durationMs': 1040,
      'subtitle': '질문',
    });

    expect(cacheHit.expiresAt, isNull);
    expect(cacheHit.durationMs, isNull);
    expect(newlyCreated.expiresAt, isNull);
    expect(newlyCreated.durationMs, 1040);
  });

  test('TTS POST 후 인증 프록시에서 audio/mpeg bytes를 내려받는다', () async {
    final adapter = _TtsAdapter();
    final repository = RemoteQuestionTtsRepository(_client(adapter));

    final audio = await repository.loadQuestionAudio(803);

    expect(adapter.requests, hasLength(2));
    final post = adapter.requests[0];
    expect(post.method, 'POST');
    expect(post.uri.path, '/api/v1/conversation-messages/803/tts');
    expect(post.data, {'voice': 'CHILD_FRIENDLY_01', 'speed': 1.0});
    expect(post.headers['Authorization'], 'Bearer test-token');
    expect(post.headers.containsKey('Idempotency-Key'), isFalse);
    final get = adapter.requests[1];
    expect(get.method, 'GET');
    expect(get.uri.path, '/api/v1/conversation-messages/803/audio');
    expect(get.headers['Authorization'], 'Bearer test-token');
    expect(get.responseType, ResponseType.bytes);
    expect(audio.bytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(audio.mimeType, 'audio/mpeg');
  });

  test('cache hit의 nullable 메타데이터와 무관하게 다운로드 후 재생한다', () async {
    final adapter = _TtsAdapter(durationMs: null);
    final repository = RemoteQuestionTtsRepository(_client(adapter));
    final player = _RecordingQuestionAudioPlayer();
    final controller = AiQuestionTtsController(repository, player);

    await controller.playQuestion(
      AiQuestion(
        messageId: 803,
        conversationId: 10,
        sequence: 1,
        text: '무엇이 보이니?',
        options: const [],
        ttsAvailable: true,
        createdAt: DateTime.utc(2026, 7, 29),
      ),
    );

    expect(adapter.requests.map((request) => request.method), ['POST', 'GET']);
    expect(player.playCount, 1);
    expect(player.bytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(controller.status, AiQuestionTtsStatus.playing);
  });

  for (final invalidUrl in [
    'https://evil.example/audio.mp3',
    '/api/v1/conversation-messages/804/audio',
    '/api/v1/conversation-messages/803/../audio',
    '/internal/tts/audio',
  ]) {
    test('잘못된 audioUrl은 GET 전에 차단한다: $invalidUrl', () async {
      final adapter = _TtsAdapter(audioUrl: invalidUrl);
      final repository = RemoteQuestionTtsRepository(_client(adapter));

      await expectLater(
        repository.loadQuestionAudio(803),
        throwsA(isA<FormatException>()),
      );

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'POST');
    });
  }

  for (final status in [401, 404, 500]) {
    test('$status TTS 실패는 기존 ApiResponseFailure로 전달한다', () async {
      final adapter = _TtsAdapter(statusCode: status);
      final repository = RemoteQuestionTtsRepository(_client(adapter));

      await expectLater(
        repository.loadQuestionAudio(803),
        throwsA(
          isA<ApiResponseFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    });
  }

  for (final status in [401, 404, 500]) {
    test('audio GET $status 실패도 기존 ApiResponseFailure로 전달한다', () async {
      final adapter = _TtsAdapter(audioStatusCode: status);
      final repository = RemoteQuestionTtsRepository(_client(adapter));

      await expectLater(
        repository.loadQuestionAudio(803),
        throwsA(
          isA<ApiResponseFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
      expect(adapter.requests.map((request) => request.method), [
        'POST',
        'GET',
      ]);
    });
  }

  test('네트워크 실패는 기존 ApiTransportFailure로 전달한다', () async {
    final repository = RemoteQuestionTtsRepository(
      _client(_TtsAdapter(transportFailure: true)),
    );

    await expectLater(
      repository.loadQuestionAudio(803),
      throwsA(isA<ApiTransportFailure>()),
    );
  });
}

ApiClient _client(HttpClientAdapter adapter) => ApiClient(
  environment: ApiEnvironment.fromBaseUrl('https://api.example.test'),
  accessTokenProvider: const _TokenProvider(),
  httpClientAdapter: adapter,
);

final class _TokenProvider implements AccessTokenProvider {
  const _TokenProvider();

  @override
  Future<String?> readAccessToken() async => 'test-token';
}

final class _TtsAdapter implements HttpClientAdapter {
  _TtsAdapter({
    this.audioUrl = '/api/v1/conversation-messages/803/audio',
    this.statusCode = 200,
    this.audioStatusCode = 200,
    this.transportFailure = false,
    this.durationMs = 1040,
  });

  final String audioUrl;
  final int statusCode;
  final int audioStatusCode;
  final bool transportFailure;
  final int? durationMs;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (transportFailure) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (statusCode != 200) {
      return ResponseBody.fromString(
        '{"success":false,"code":"TTS_FAILURE","message":"failed"}',
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (options.method == 'POST') {
      return ResponseBody.fromString(
        '{"success":true,"data":{'
        '"audioUrl":"$audioUrl",'
        '"expiresAt":null,'
        '"durationMs":${durationMs ?? 'null'},'
        '"subtitle":"질문"}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (audioStatusCode != 200) {
      return ResponseBody.fromString(
        '{"success":false,"code":"CONVERSATION_AUDIO_NOT_AVAILABLE",'
        '"message":"failed"}',
        audioStatusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromBytes(
      [1, 2, 3, 4],
      200,
      headers: {
        Headers.contentTypeHeader: ['audio/mpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _RecordingQuestionAudioPlayer implements QuestionAudioPlayer {
  int playCount = 0;
  Uint8List? bytes;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCount += 1;
    this.bytes = bytes;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
