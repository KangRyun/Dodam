import 'package:dio/dio.dart';

import '../config/api_environment.dart';
import 'api_error.dart';
import 'api_failure.dart';
import 'auth/access_token_provider.dart';
import 'auth/auth_header_interceptor.dart';
import 'public_api_path.dart';

final class ApiClient {
  ApiClient({
    required ApiEnvironment environment,
    AccessTokenProvider? accessTokenProvider,
    List<Interceptor> interceptors = const [],
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: environment.apiBaseUri.toString(),
           connectTimeout: connectTimeout,
           sendTimeout: sendTimeout,
           receiveTimeout: receiveTimeout,
           headers: const {'Accept': 'application/json'},
         ),
       ) {
    if (accessTokenProvider != null) {
      _dio.interceptors.add(AuthHeaderInterceptor(accessTokenProvider));
    }
    _dio.interceptors.addAll(interceptors);
  }

  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request(
    () => _dio.get<T>(
      PublicApiPath.normalize(path),
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request(
    () => _dio.post<T>(
      PublicApiPath.normalize(path),
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request(
    () => _dio.patch<T>(
      PublicApiPath.normalize(path),
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request(
    () => _dio.delete<T>(
      PublicApiPath.normalize(path),
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<T>> _request<T>(Future<Response<T>> Function() send) async {
    try {
      return await send();
    } on DioException catch (exception) {
      throw _toFailure(exception);
    }
  }

  ApiFailure _toFailure(DioException exception) {
    if (exception.type == DioExceptionType.badResponse) {
      final body = exception.response?.data;
      return ApiResponseFailure(
        statusCode: exception.response?.statusCode,
        error: ApiError.tryParse(body),
        responseBody: body,
      );
    }

    final type = switch (exception.type) {
      DioExceptionType.connectionTimeout =>
        ApiTransportFailureType.connectionTimeout,
      DioExceptionType.sendTimeout => ApiTransportFailureType.sendTimeout,
      DioExceptionType.receiveTimeout => ApiTransportFailureType.receiveTimeout,
      DioExceptionType.transformTimeout =>
        ApiTransportFailureType.transformTimeout,
      DioExceptionType.connectionError => ApiTransportFailureType.connection,
      DioExceptionType.cancel => ApiTransportFailureType.cancelled,
      DioExceptionType.badCertificate ||
      DioExceptionType.unknown ||
      DioExceptionType.badResponse => ApiTransportFailureType.unknown,
    };
    return ApiTransportFailure(type: type, cause: exception.error ?? exception);
  }
}
