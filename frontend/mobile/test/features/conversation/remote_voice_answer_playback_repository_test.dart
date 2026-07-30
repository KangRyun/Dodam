import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

const _maxBytes = 20 * 1024 * 1024;

void main() {
  test('실제 message audio endpoint에서 JWT로 stream을 조회한다', () async {
    final adapter = _AudioAdapter();
    final repository = RemoteVoiceAnswerPlaybackRepository(_client(adapter));

    final audio = await repository.loadVoiceAnswerAudio(804);

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/conversation-messages/804/audio');
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(request.headers['Accept'], 'audio/*');
    expect(request.responseType, ResponseType.stream);
    expect(audio.bytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(audio.mimeType, 'audio/webm');
  });

  for (final mimeType in [
    'audio/webm',
    'audio/mp4',
    'audio/wav',
    'audio/mpeg',
  ]) {
    test('$mimeType 응답을 허용한다', () async {
      final repository = RemoteVoiceAnswerPlaybackRepository(
        _client(_AudioAdapter(contentType: mimeType)),
      );

      final audio = await repository.loadVoiceAnswerAudio(804);

      expect(audio.mimeType, mimeType);
    });
  }

  test('MIME 대소문자와 parameter를 정규화한다', () async {
    final repository = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(contentType: 'Audio/MP4; codecs=mp4a.40.2')),
    );

    final audio = await repository.loadVoiceAnswerAudio(804);

    expect(audio.mimeType, 'audio/mp4');
  });

  for (final status in [401, 403, 404, 422, 500]) {
    test('$status 응답은 ApiResponseFailure로 전달한다', () async {
      final repository = RemoteVoiceAnswerPlaybackRepository(
        _client(_AudioAdapter(statusCode: status)),
      );

      await expectLater(
        repository.loadVoiceAnswerAudio(804),
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

  test('network 오류는 ApiTransportFailure로 전달한다', () async {
    final repository = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(transportFailure: true)),
    );

    await expectLater(
      repository.loadVoiceAnswerAudio(804),
      throwsA(
        isA<ApiTransportFailure>().having(
          (failure) => failure.type,
          'type',
          ApiTransportFailureType.connection,
        ),
      ),
    );
  });

  test('receive timeout은 재시도 가능한 transport failure다', () async {
    final repository = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(streamReceiveTimeout: true)),
    );

    await expectLater(
      repository.loadVoiceAnswerAudio(804),
      throwsA(
        isA<ApiTransportFailure>().having(
          (failure) => failure.type,
          'type',
          ApiTransportFailureType.receiveTimeout,
        ),
      ),
    );
  });

  test('빈 audio와 잘못된 content type은 typed failure다', () async {
    final empty = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(bytes: const [])),
    );
    final json = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(contentType: 'application/json')),
    );

    await expectLater(
      empty.loadVoiceAnswerAudio(804),
      throwsA(_validation(VoiceAnswerPlaybackValidationReason.emptyAudio)),
    );
    await expectLater(
      json.loadVoiceAnswerAudio(804),
      throwsA(
        _validation(VoiceAnswerPlaybackValidationReason.unsupportedMimeType),
      ),
    );
  });

  test('유효하지 않은 Content-Length는 typed failure다', () async {
    final repository = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(contentLength: 'not-a-number')),
    );

    await expectLater(
      repository.loadVoiceAnswerAudio(804),
      throwsA(_validation(VoiceAnswerPlaybackValidationReason.invalidResponse)),
    );
  });

  test('Content-Length가 있으면 20MiB 초과를 수신 전에 거부한다', () async {
    final adapter = _AudioAdapter(contentLength: '${_maxBytes + 1}');
    final repository = RemoteVoiceAnswerPlaybackRepository(_client(adapter));

    await expectLater(
      repository.loadVoiceAnswerAudio(804),
      throwsA(_validation(VoiceAnswerPlaybackValidationReason.tooLarge)),
    );
  });

  test('Content-Length가 없어도 누적 20MiB 정확 경계는 허용한다', () async {
    final repository = RemoteVoiceAnswerPlaybackRepository(
      _client(_AudioAdapter(bytes: Uint8List(_maxBytes))),
    );

    final audio = await repository.loadVoiceAnswerAudio(804);

    expect(audio.bytes, hasLength(_maxBytes));
  });

  test('Content-Length가 없어도 누적 20MiB+1은 조기에 거부한다', () async {
    final repository = RemoteVoiceAnswerPlaybackRepository(
      _client(
        _AudioAdapter(
          chunks: [
            Uint8List(_maxBytes),
            Uint8List.fromList([1]),
          ],
        ),
      ),
    );

    await expectLater(
      repository.loadVoiceAnswerAudio(804),
      throwsA(_validation(VoiceAnswerPlaybackValidationReason.tooLarge)),
    );
  });

  test('유효하지 않은 messageId는 네트워크 요청 전에 typed failure다', () async {
    final adapter = _AudioAdapter();
    final repository = RemoteVoiceAnswerPlaybackRepository(_client(adapter));

    await expectLater(
      repository.loadVoiceAnswerAudio(0),
      throwsA(
        _validation(VoiceAnswerPlaybackValidationReason.invalidMessageId),
      ),
    );

    expect(adapter.requests, isEmpty);
  });

  test('호출자가 다운로드를 취소하면 cancelled failure로 끝난다', () async {
    final adapter = _AudioAdapter(waitForCancel: true);
    final repository = RemoteVoiceAnswerPlaybackRepository(_client(adapter));
    final cancellation = VoiceAnswerPlaybackCancellation();

    final request = repository.loadVoiceAnswerAudio(
      804,
      cancellation: cancellation,
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();

    await expectLater(
      request,
      throwsA(
        isA<ApiTransportFailure>().having(
          (failure) => failure.type,
          'type',
          ApiTransportFailureType.cancelled,
        ),
      ),
    );
  });
}

Matcher _validation(VoiceAnswerPlaybackValidationReason reason) =>
    isA<VoiceAnswerPlaybackValidationFailure>().having(
      (failure) => failure.reason,
      'reason',
      reason,
    );

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

final class _AudioAdapter implements HttpClientAdapter {
  _AudioAdapter({
    this.statusCode = 200,
    this.contentType = 'audio/webm',
    this.bytes = const [1, 2, 3, 4],
    this.chunks,
    this.contentLength,
    this.transportFailure = false,
    this.streamReceiveTimeout = false,
    this.waitForCancel = false,
  });

  final int statusCode;
  final String contentType;
  final List<int> bytes;
  final List<Uint8List>? chunks;
  final String? contentLength;
  final bool transportFailure;
  final bool streamReceiveTimeout;
  final bool waitForCancel;
  final List<RequestOptions> requests = [];
  int streamListenCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (waitForCancel) {
      await cancelFuture;
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled by caller',
      );
    }
    if (transportFailure) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (statusCode != 200) {
      return ResponseBody.fromString(
        '{"success":false,"code":"CONVERSATION_AUDIO_NOT_AVAILABLE",'
        '"message":"failed"}',
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    final responseHeaders = <String, List<String>>{
      Headers.contentTypeHeader: [contentType],
      if (contentLength != null) Headers.contentLengthHeader: [contentLength!],
    };
    final streamChunks =
        chunks ??
        [bytes is Uint8List ? bytes as Uint8List : Uint8List.fromList(bytes)];
    return ResponseBody(
      Stream<Uint8List>.multi((controller) {
        streamListenCount += 1;
        if (streamReceiveTimeout) {
          controller.addError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            ),
          );
          controller.close();
          return;
        }
        for (final chunk in streamChunks) {
          controller.add(chunk);
        }
        controller.close();
      }),
      200,
      headers: responseHeaders,
    );
  }

  @override
  void close({bool force = false}) {}
}
