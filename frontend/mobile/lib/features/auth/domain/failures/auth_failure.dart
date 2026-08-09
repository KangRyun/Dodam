enum AuthFailureType {
  cancelled,
  network,
  providerRejected,
  serverRejected,
  accountSuspended,
  accountWithdrawn,
  invalidCredential,
  configuration,
  tokenExpired,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure({
    required this.type,
    required this.message,
    this.code,
    this.cause,
  });

  final AuthFailureType type;
  final String message;
  final String? code;
  final Object? cause;

  bool get canRetry => switch (type) {
    AuthFailureType.network ||
    AuthFailureType.serverRejected ||
    AuthFailureType.unknown => true,
    _ => false,
  };

  @override
  String toString() =>
      'AuthFailure(type: $type, code: $code, message: $message)';
}
