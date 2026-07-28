import 'package:dio/dio.dart';

import 'access_token_provider.dart';
import 'token_refresher.dart';

/// 현재 Access Token을 인증 요청 헤더에 첨부
final class AuthHeaderInterceptor extends Interceptor {
  AuthHeaderInterceptor(this._tokenProvider);

  final AccessTokenProvider _tokenProvider;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await _tokenProvider.readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }
}

/// 401 응답에서 Token을 재발급하고 원 요청을 한 번 재시도
final class AuthTokenRetryInterceptor extends Interceptor {
  AuthTokenRetryInterceptor(
    this._dio,
    this._tokenProvider,
    this._tokenRefresher,
  );

  final Dio _dio;
  final AccessTokenProvider _tokenProvider;
  final TokenRefresher _tokenRefresher;

  static const _retriedKey = 'auth-token-retried';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final canRefresh =
        err.response?.statusCode == 401 &&
        request.extra[_retriedKey] != true &&
        !_isAuthRequest(request.path);

    if (!canRefresh) {
      handler.next(err);
      return;
    }

    final refreshed = await _tokenRefresher.refreshAccessToken();
    if (!refreshed) {
      handler.next(err);
      return;
    }

    final accessToken = await _tokenProvider.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      handler.next(err);
      return;
    }

    request.extra[_retriedKey] = true;
    request.headers['Authorization'] = 'Bearer $accessToken';
    // multipart 본문(FormData)은 첫 전송에서 finalize돼 그대로는 재전송할 수 없다.
    // 토큰 갱신 후 재요청 시 clone으로 새 FormData를 만들어야 "The FormData has
    // already been finalized" 오류 없이 초안·완료·음성 업로드가 재시도된다.
    if (request.data is FormData) {
      request.data = (request.data as FormData).clone();
    }

    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _isAuthRequest(String path) {
    final segments = Uri.tryParse(path)?.pathSegments ?? const <String>[];
    final authIndex = segments.indexOf('auth');
    return authIndex >= 0 && authIndex + 1 < segments.length;
  }
}
