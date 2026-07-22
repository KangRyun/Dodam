import 'package:dio/dio.dart';

import 'access_token_provider.dart';

/// Adds the current access token without owning authentication state.
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
