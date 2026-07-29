import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/data/repositories/remote_activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 활동 상세(`GET /api/v1/drawing-sessions/{id}`)와 대화 내역
/// (`GET /api/v1/conversations/{id}/messages`) 연동 계약 테스트.
/// 실제 네트워크 없이 [HttpClientAdapter]를 갈아끼워 검증한다.
void main() {
  test('상세 조회는 공개 API 경로로 인증 헤더와 함께 요청한다', () async {
    final adapter = _StubAdapter([_okResponse(_detailData())]);
    final repository = RemoteActivityRepository(_client(adapter));

    final detail = await repository.getActivity(120);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/drawing-sessions/120');
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(detail.activityId, 120);
    expect(detail.conversationId, 77);
  });

  test('상세 응답의 conversationId가 null이면 그대로 null이다', () async {
    final repository = RemoteActivityRepository(
      _client(
        _StubAdapter([
          _okResponse({..._detailData(), 'conversationId': null}),
        ]),
      ),
    );

    final detail = await repository.getActivity(120);

    expect(detail.conversationId, isNull);
  });

  test('메시지 조회는 대화 경로와 page·size 파라미터를 전달한다', () async {
    final adapter = _StubAdapter([
      _okResponse(_messagePage(messages: [_question(801, 1)], hasNext: false)),
    ]);
    final repository = RemoteActivityRepository(_client(adapter));

    final messages = await repository.getConversationMessages(77);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/conversations/77/messages');
    expect(request.queryParameters, {'page': 0, 'size': 100});
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(messages.single.messageId, 801);
  });

  test('봉투 없이 본문만 오는 응답도 그대로 파싱한다', () async {
    final repository = RemoteActivityRepository(
      _client(
        _StubAdapter([
          _rawResponse(
            _messagePage(messages: [_question(801, 1)], hasNext: false),
          ),
        ]),
      ),
    );

    final messages = await repository.getConversationMessages(77);

    expect(messages.single.messageId, 801);
  });

  test('여러 페이지를 순서대로 이어 읽고 중복 messageId는 한 번만 담는다', () async {
    final adapter = _StubAdapter([
      _okResponse(
        _messagePage(
          messages: [_question(803, 3), _question(801, 1)],
          hasNext: true,
        ),
      ),
      _okResponse(
        _messagePage(
          // 803은 첫 페이지와 겹치고 805는 새 메시지다.
          messages: [_question(803, 3), _question(805, 5)],
          hasNext: false,
        ),
      ),
    ]);
    final repository = RemoteActivityRepository(_client(adapter));

    final messages = await repository.getConversationMessages(77);

    expect(adapter.requests.map((request) => request.queryParameters['page']), [
      0,
      1,
    ]);
    expect(messages.map((message) => message.messageId).toList(), [
      801,
      803,
      805,
    ]);
  });

  test('hasNext가 true여도 빈 페이지에서 멈춘다', () async {
    final adapter = _StubAdapter([
      _okResponse(_messagePage(messages: [_question(801, 1)], hasNext: true)),
      _okResponse(_messagePage(messages: const [], hasNext: true)),
    ]);
    final repository = RemoteActivityRepository(_client(adapter));

    final messages = await repository.getConversationMessages(77);

    expect(adapter.requests, hasLength(2));
    expect(messages.single.messageId, 801);
  });

  test('nullable 필드가 모두 빠진 메시지도 파싱한다', () async {
    final repository = RemoteActivityRepository(
      _client(
        _StubAdapter([
          _okResponse(
            _messagePage(
              messages: const [
                {
                  'messageId': 809,
                  'parentMessageId': null,
                  'sequence': 9,
                  'senderType': 'CHILD',
                  'messageType': 'ANSWER_VOICE',
                  'rawText': null,
                  'sttText': null,
                  'speechStatus': null,
                  'sttConfidence': null,
                  'needsGuardianConfirmation': false,
                  'isSkipped': false,
                  'options': <Map<String, dynamic>>[],
                  'selectedResponse': null,
                  'targetObject': null,
                  'createdAt': null,
                },
              ],
              hasNext: false,
            ),
          ),
        ]),
      ),
    );

    final message = (await repository.getConversationMessages(77)).single;

    expect(message.messageId, 809);
    expect(message.sttText, isNull);
    expect(message.speechStatus, isNull);
    expect(message.options, isEmpty);
    expect(message.selectedResponse, isNull);
    expect(message.createdAt, isNull);
  });

  test('403은 ApiResponseFailure로 올라온다', () async {
    final repository = RemoteActivityRepository(
      _client(
        _StubAdapter([
          _errorResponse(
            403,
            'CONVERSATION_ACCESS_DENIED',
            '대화에 접근할 권한이 없습니다.',
          ),
        ]),
      ),
    );

    await expectLater(
      repository.getConversationMessages(77),
      throwsA(
        isA<ApiResponseFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 403)
            .having(
              (failure) => failure.error?.code,
              'code',
              'CONVERSATION_ACCESS_DENIED',
            ),
      ),
    );
  });

  test('네트워크 단절은 ApiTransportFailure로 올라오고 재시도할 수 있다', () async {
    final adapter = _FlakyAdapter(
      _okResponse(_messagePage(messages: [_question(801, 1)], hasNext: false)),
    );
    final repository = RemoteActivityRepository(_client(adapter));

    await expectLater(
      repository.getConversationMessages(77),
      throwsA(
        isA<ApiTransportFailure>().having(
          (failure) => failure.type,
          'type',
          ApiTransportFailureType.connection,
        ),
      ),
    );

    final messages = await repository.getConversationMessages(77);
    expect(messages.single.messageId, 801);
  });
}

ApiClient _client(HttpClientAdapter adapter) => ApiClient(
  environment: ApiEnvironment.fromBaseUrl('https://api.example.com'),
  accessTokenProvider: const _FixedToken('test-token'),
  httpClientAdapter: adapter,
);

Map<String, dynamic> _detailData() => {
  'drawingSessionId': 120,
  'child': {'childId': 3, 'nickname': '도담이'},
  'drawingType': {'drawingTypeId': 5, 'code': 'ART_DIARY', 'name': '그림일기'},
  'inputMethod': 'CANVAS',
  'title': '우리 가족',
  'selectedEmotions': ['HAPPY'],
  'sessionStatus': 'COMPLETED',
  'currentStage': 'COMPLETED',
  'latestAsset': null,
  'latestAnalysis': null,
  'conversationId': 77,
  'reportId': 501,
  'startedAt': '2026-07-20T09:40:00Z',
  'completedAt': '2026-07-20T10:03:00Z',
  'recoverableDraft': false,
};

Map<String, dynamic> _question(int messageId, int sequence) => {
  'messageId': messageId,
  'parentMessageId': null,
  'sequence': sequence,
  'senderType': 'AI',
  'messageType': 'QUESTION',
  'rawText': '무엇을 그렸어?',
  'options': <Map<String, dynamic>>[],
  'isSkipped': false,
  'createdAt': '2026-07-20T09:52:00',
};

Map<String, dynamic> _messagePage({
  required List<Map<String, dynamic>> messages,
  required bool hasNext,
}) => {
  'content': messages,
  'page': 0,
  'size': 100,
  'totalElements': messages.length,
  'totalPages': hasNext ? 2 : 1,
  'first': true,
  'last': !hasNext,
  'hasNext': hasNext,
};

ResponseBody _okResponse(Map<String, dynamic> data) => _json(200, {
  'success': true,
  'code': 'COMMON_200',
  'message': '요청이 성공했습니다.',
  'data': data,
});

ResponseBody _rawResponse(Map<String, dynamic> data) => _json(200, data);

ResponseBody _errorResponse(int status, String code, String message) => _json(
  status,
  {'success': false, 'code': code, 'message': message, 'data': null},
);

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 미리 정해둔 응답을 요청 순서대로 돌려준다. 준비한 응답을 다 쓰면 마지막
/// 응답을 반복해 과잉 요청을 눈에 띄게 만들지 않고 검증은 요청 수로 한다.
final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final index = requests.length - 1;
    return index < _responses.length ? _responses[index] : _responses.last;
  }

  @override
  void close({bool force = false}) {}
}

/// 첫 요청만 끊고 그다음부터 성공한다 — 재시도 경로 검증용.
final class _FlakyAdapter implements HttpClientAdapter {
  _FlakyAdapter(this._response);

  final ResponseBody _response;
  int _calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _calls += 1;
    if (_calls == 1) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return _response;
  }

  @override
  void close({bool force = false}) {}
}

final class _FixedToken implements AccessTokenProvider {
  const _FixedToken(this._token);

  final String _token;

  @override
  Future<String?> readAccessToken() async => _token;
}
