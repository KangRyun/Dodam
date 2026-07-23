final class ApiValidationError {
  const ApiValidationError({required this.field, required this.reason});

  factory ApiValidationError.fromJson(Map<String, dynamic> json) {
    return ApiValidationError(
      field: json['field'] as String,
      reason: json['reason'] as String,
    );
  }

  final String field;
  final String reason;
}

/// Error body defined by API common contract v1.0.
final class ApiError {
  const ApiError({
    required this.timestamp,
    required this.path,
    required this.code,
    required this.message,
    this.errors = const [],
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return ApiError(
      timestamp: json['timestamp'] as String,
      path: json['path'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      errors: rawErrors == null
          ? const []
          : (rawErrors as List<dynamic>)
                .map(
                  (error) => ApiValidationError.fromJson(
                    error as Map<String, dynamic>,
                  ),
                )
                .toList(growable: false),
    );
  }

  static ApiError? tryParse(Object? value) {
    if (value is! Map) return null;
    try {
      return ApiError.fromJson(Map<String, dynamic>.from(value));
    } on Object {
      return null;
    }
  }

  final String timestamp;
  final String path;
  final String code;
  final String message;
  final List<ApiValidationError> errors;
}
