final class ApiValidationError {
  const ApiValidationError({required this.field, required this.reason});

  factory ApiValidationError.fromJson(Map<String, dynamic> json) {
    return ApiValidationError(
      field: json['field'] as String,
      reason: (json['message'] ?? json['reason']) as String,
    );
  }

  final String field;
  final String reason;
}

/// API 공통 계약의 오류 응답을 역직렬화한다.
///
/// 현재 응답의 `data.fieldErrors`와 이전 응답의 최상위 `errors`를 모두
/// 허용해 서버 배포 전환 중에도 필드 오류를 일관되게 제공한다.
final class ApiError {
  const ApiError({
    this.timestamp,
    this.path,
    required this.code,
    required this.message,
    this.errors = const [],
    this.globalErrors = const [],
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final rawErrors = json['errors'] ?? _fieldErrorsFromData(data);
    final rawGlobalErrors = _globalErrorsFromData(data);
    return ApiError(
      timestamp: json['timestamp'] as String?,
      path: json['path'] as String?,
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
      globalErrors: rawGlobalErrors == null
          ? const []
          : List<String>.from(rawGlobalErrors),
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

  final String? timestamp;
  final String? path;
  final String code;
  final String message;
  final List<ApiValidationError> errors;
  final List<String> globalErrors;

  static Object? _fieldErrorsFromData(Object? data) {
    if (data is Map && data['fieldErrors'] is List) {
      return data['fieldErrors'];
    }
    if (data is Map && data['errors'] is List) {
      return data['errors'];
    }
    return null;
  }

  static List<dynamic>? _globalErrorsFromData(Object? data) {
    if (data is Map && data['globalErrors'] is List) {
      return data['globalErrors']! as List<dynamic>;
    }
    return null;
  }
}
