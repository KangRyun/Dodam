import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/report/data/repositories/remote_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// REPORT-02 `GET /api/v1/reports/{reportId}` 연동 계약 테스트.
/// 실제 네트워크 없이 [HttpClientAdapter]를 갈아끼워 검증한다.
void main() {
  test('상세 조회는 공개 API 경로로 인증 헤더와 함께 요청한다', () async {
    final adapter = _StubAdapter(_okResponse(_detailData()));
    final repository = RemoteReportRepository(_client(adapter));

    await repository.getReport(500);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/reports/500');
    expect(request.headers['Authorization'], 'Bearer test-token');
  });

  test('공통 봉투의 data를 벗겨 DTO로 만든다', () async {
    final repository = RemoteReportRepository(
      _client(_StubAdapter(_okResponse(_detailData()))),
    );

    final report = await repository.getReport(500);

    expect(report.reportId, 500);
    expect(report.reportStatus, 'COMPLETED');
    expect(report.drawingSession!.title, '우리 가족');
    expect(report.childExpression!.representativeUtterances.single.text, '좋아');
    expect(report.limitations, ['이 리포트는 진단이 아닙니다']);
  });

  test('봉투 없이 본문만 오는 응답도 그대로 파싱한다', () async {
    final repository = RemoteReportRepository(
      _client(_StubAdapter(_rawResponse(_detailData()))),
    );

    final report = await repository.getReport(500);

    expect(report.reportId, 500);
  });

  test('401은 ApiResponseFailure로 올라온다', () async {
    final repository = RemoteReportRepository(
      _client(_StubAdapter(_errorResponse(401, 'AUTH_401_006', '인증이 필요합니다.'))),
    );

    await expectLater(
      repository.getReport(500),
      throwsA(
        isA<ApiResponseFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 401)
            .having((failure) => failure.isUnauthorized, 'isUnauthorized', true)
            .having((failure) => failure.error?.code, 'code', 'AUTH_401_006'),
      ),
    );
  });

  test('403 REPORT_ACCESS_DENIED는 보호자 권한 오류로 올라온다', () async {
    final repository = RemoteReportRepository(
      _client(
        _StubAdapter(
          _errorResponse(403, 'REPORT_ACCESS_DENIED', '리포트에 접근할 권한이 없습니다.'),
        ),
      ),
    );

    await expectLater(
      repository.getReport(500),
      throwsA(
        isA<ApiResponseFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 403)
            .having((failure) => failure.isForbidden, 'isForbidden', true)
            .having(
              (failure) => failure.error?.code,
              'code',
              'REPORT_ACCESS_DENIED',
            ),
      ),
    );
  });

  test('404 REPORT_NOT_FOUND는 없음 오류로 올라온다', () async {
    final repository = RemoteReportRepository(
      _client(
        _StubAdapter(
          _errorResponse(404, 'REPORT_NOT_FOUND', '리포트를 찾을 수 없습니다.'),
        ),
      ),
    );

    await expectLater(
      repository.getReport(500),
      throwsA(
        isA<ApiResponseFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 404)
            .having(
              (failure) => failure.error?.code,
              'code',
              'REPORT_NOT_FOUND',
            ),
      ),
    );
  });

  test('네트워크 단절은 ApiTransportFailure로 올라온다', () async {
    final repository = RemoteReportRepository(
      _client(_ThrowingAdapter(DioExceptionType.connectionError)),
    );

    await expectLater(
      repository.getReport(500),
      throwsA(
        isA<ApiTransportFailure>().having(
          (failure) => failure.type,
          'type',
          ApiTransportFailureType.connection,
        ),
      ),
    );
  });

  test('타임아웃도 ApiTransportFailure로 올라온다', () async {
    final repository = RemoteReportRepository(
      _client(_ThrowingAdapter(DioExceptionType.receiveTimeout)),
    );

    await expectLater(
      repository.getReport(500),
      throwsA(
        isA<ApiTransportFailure>().having(
          (failure) => failure.type,
          'type',
          ApiTransportFailureType.receiveTimeout,
        ),
      ),
    );
  });

  test('500은 ApiResponseFailure로 올라온다', () async {
    final repository = RemoteReportRepository(
      _client(
        _StubAdapter(_errorResponse(500, 'COMMON_500', '서버 오류가 발생했습니다.')),
      ),
    );

    await expectLater(
      repository.getReport(500),
      throwsA(
        isA<ApiResponseFailure>().having(
          (failure) => failure.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });
}

ApiClient _client(HttpClientAdapter adapter) => ApiClient(
  environment: ApiEnvironment.fromBaseUrl('https://api.example.com'),
  accessTokenProvider: const _FixedToken('test-token'),
  httpClientAdapter: adapter,
);

Map<String, dynamic> _detailData() => {
  'reportId': 500,
  'reportVersion': 1,
  'reportStatus': 'COMPLETED',
  'drawingSession': {
    'drawingSessionId': 100,
    'childId': 1,
    'drawingTypeCode': 'ART_DIARY',
    'drawingTypeName': '그림일기',
    'title': '우리 가족',
    'inputMethod': 'CANVAS',
    'startedAt': '2026-07-21T02:00:00',
    'completedAt': '2026-07-21T02:05:00',
    'durationMs': 300000,
  },
  'drawing': {
    'finalImageUrl': 'https://cdn.example/final.png',
    'thumbnailUrl': null,
  },
  'childExpression': {
    'selectedEmotions': ['HAPPY'],
    'expressedEmotionText': null,
    'representativeUtterances': [
      {
        'messageId': 804,
        'text': '좋아',
        'source': 'STT',
        'sttNeedsConfirmation': false,
      },
    ],
  },
  'activityFacts': {
    'detectedObjects': <String>[],
    'drawingDurationMs': null,
    'pauseCount': null,
    'eraseCount': null,
    'pressureAvailable': false,
    'notes': <String>[],
  },
  'conversationSummary': {
    'questionCount': 5,
    'answeredCount': 4,
    'skippedCount': 1,
    'summary': null,
  },
  'guardianConversationGuide': <String>[],
  'limitations': ['이 리포트는 진단이 아닙니다'],
  'expertReview': {'status': 'NOT_REQUESTED', 'available': false},
  'createdAt': '2026-07-21T02:06:00',
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

final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._response);

  final ResponseBody _response;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _response;
  }

  @override
  void close({bool force = false}) {}
}

final class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this._type);

  final DioExceptionType _type;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException(requestOptions: options, type: _type);

  @override
  void close({bool force = false}) {}
}

final class _FixedToken implements AccessTokenProvider {
  const _FixedToken(this._token);

  final String _token;

  @override
  Future<String?> readAccessToken() async => _token;
}
