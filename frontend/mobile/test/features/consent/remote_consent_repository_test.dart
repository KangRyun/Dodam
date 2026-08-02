import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/consent/data/repositories/remote_consent_repository.dart';
import 'package:dodam/features/consent/domain/repositories/consent_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('범위를 주지 않으면 targetScope Query 자체를 보내지 않는다', () async {
    // 서버는 targetScope가 없을 때만 전 범위를 돌려준다. 빈 문자열을 보내면
    // Enum 변환이 400으로 떨어지므로 키가 남아 있어도 안 된다.
    final adapter = _RecordingAdapter([_termsResponse()]);
    final repository = RemoteConsentRepository(_apiClient(adapter));

    await repository.getTerms();

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, 'consents/terms');
    expect(request.queryParameters, isEmpty);
    expect(request.uri.path, '/api/v1/consents/terms');
    expect(request.uri.query, isEmpty);
  });

  test('보호자 범위를 주면 targetScope=USER로 보낸다', () async {
    final adapter = _RecordingAdapter([_termsResponse()]);
    final repository = RemoteConsentRepository(_apiClient(adapter));

    await repository.getTerms(ConsentTargetScope.user);

    final request = adapter.requests.single;
    expect(request.queryParameters, {'targetScope': 'USER'});
    expect(request.uri.query, 'targetScope=USER');
  });

  test('아동 범위를 주면 targetScope=CHILD로 보낸다', () async {
    final adapter = _RecordingAdapter([_termsResponse()]);
    final repository = RemoteConsentRepository(_apiClient(adapter));

    await repository.getTerms(ConsentTargetScope.child);

    final request = adapter.requests.single;
    expect(request.queryParameters, {'targetScope': 'CHILD'});
    expect(request.uri.query, 'targetScope=CHILD');
  });

  test('공통 응답 봉투를 한 번만 벗겨 약관 목록으로 바꾼다', () async {
    final adapter = _RecordingAdapter([_termsResponse()]);
    final repository = RemoteConsentRepository(_apiClient(adapter));

    final terms = await repository.getTerms();

    expect(terms.length, 2);
    expect(terms.first.termId, 1);
    expect(terms.first.termCode, 'SERVICE_TOS');
    expect(terms.first.title, '서비스 이용약관');
    expect(terms.first.required, isTrue);
    expect(terms.first.targetScope, ConsentTargetScope.user);
    expect(terms.first.contentHtml, '<p>제1조(목적)</p>');
    expect(terms.last.termId, 5);
    expect(terms.last.targetScope, ConsentTargetScope.child);
    expect(terms.last.required, isFalse);
  });
}

ApiClient _apiClient(HttpClientAdapter adapter) => ApiClient(
  environment: ApiEnvironment.fromBaseUrl('https://example.test'),
  httpClientAdapter: adapter,
);

ResponseBody _termsResponse() => ResponseBody.fromString(
  jsonEncode({
    'success': true,
    'code': 'COMMON_200',
    'message': '요청에 성공했습니다.',
    'data': [
      {
        'termId': 1,
        'termCode': 'SERVICE_TOS',
        'targetScope': 'USER',
        'required': true,
        'version': 'v1',
        'title': '서비스 이용약관',
        'contentUrl': null,
        'contentHtml': '<p>제1조(목적)</p>',
        'effectiveAt': '2020-01-01T00:00:00Z',
      },
      {
        'termId': 5,
        'termCode': 'VOICE_PROCESSING',
        'targetScope': 'CHILD',
        'required': false,
        'version': 'v1',
        'title': '음성 데이터 처리',
        'contentUrl': null,
        'contentHtml': null,
        'effectiveAt': '2020-01-01T00:00:00Z',
      },
    ],
  }),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}
