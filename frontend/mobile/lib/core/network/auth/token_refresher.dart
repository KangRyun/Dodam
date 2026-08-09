import 'dart:async';

/// Extension point for a future auth-owned refresh implementation.
abstract interface class TokenRefresher {
  Future<bool> refreshAccessToken();
}

/// Prevents concurrent 401 responses from starting duplicate refresh calls.
///
/// This class only coordinates a supplied refresher. It intentionally does not
/// know about refresh-token storage, cookies, or AuthRepository.
final class SingleFlightTokenRefresher implements TokenRefresher {
  SingleFlightTokenRefresher(this._refresh);

  final Future<bool> Function() _refresh;
  Future<bool>? _inFlight;

  @override
  Future<bool> refreshAccessToken() {
    return _inFlight ??= _run();
  }

  Future<bool> _run() async {
    try {
      return await _refresh();
    } finally {
      _inFlight = null;
    }
  }
}
