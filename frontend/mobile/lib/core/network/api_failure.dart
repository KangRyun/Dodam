import 'api_error.dart';

sealed class ApiFailure implements Exception {
  const ApiFailure();
}

/// An HTTP response that was not successful.
final class ApiResponseFailure extends ApiFailure {
  const ApiResponseFailure({
    required this.statusCode,
    required this.error,
    this.responseBody,
  });

  final int? statusCode;
  final ApiError? error;
  final Object? responseBody;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() =>
      'ApiResponseFailure(statusCode: $statusCode, code: ${error?.code})';
}

enum ApiTransportFailureType {
  connectionTimeout,
  sendTimeout,
  receiveTimeout,
  transformTimeout,
  connection,
  cancelled,
  unknown,
}

/// A failure where no valid HTTP error response was received.
final class ApiTransportFailure extends ApiFailure {
  const ApiTransportFailure({required this.type, this.cause});

  final ApiTransportFailureType type;
  final Object? cause;

  @override
  String toString() => 'ApiTransportFailure(type: $type, cause: $cause)';
}
