import 'package:flutter/foundation.dart';

import '../domain/repositories/drawing_repository.dart';

enum ActivityCompletionStatus {
  idle,
  polling,
  completed,
  terminalFailure,
  pollingFailure,
}

/// 접수된 그림 활동의 비동기 완료 상태 조회를 관리한다.
final class ActivityCompletionController extends ChangeNotifier {
  ActivityCompletionController.forStatus(
    this._repository, {
    required this.sessionId,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 30,
  }) : assert(maxPollAttempts > 0);

  final DrawingRepository _repository;
  final int sessionId;
  final Duration pollInterval;
  final int maxPollAttempts;

  ActivityCompletionStatus status = ActivityCompletionStatus.idle;
  bool _disposed = false;

  /// Drawing Session이 `COMPLETED` 또는 `FAILED`가 될 때까지 조회한다.
  ///
  /// 조회 실패나 제한 횟수 초과는 활동 실패로 단정하지 않고
  /// [ActivityCompletionStatus.pollingFailure]로 구분한다.
  ///
  /// @return 세션이 `COMPLETED` 상태에 도달했으면 `true`
  Future<bool> pollUntilTerminal() async {
    if (_disposed || status == ActivityCompletionStatus.polling) return false;
    _setStatus(ActivityCompletionStatus.polling);

    try {
      for (var attempt = 0; attempt < maxPollAttempts; attempt += 1) {
        if (_disposed) return false;
        final session = await _repository.getSession(sessionId);
        if (_disposed) return false;
        if (session.sessionStatus == 'COMPLETED' &&
            session.currentStage == 'COMPLETED') {
          _setStatus(ActivityCompletionStatus.completed);
          return true;
        }
        if (session.sessionStatus == 'FAILED') {
          _setStatus(ActivityCompletionStatus.terminalFailure);
          return false;
        }
        if (session.sessionStatus != 'IN_PROGRESS' ||
            session.currentStage != 'REPORTING') {
          _setStatus(ActivityCompletionStatus.pollingFailure);
          return false;
        }
        if (attempt + 1 < maxPollAttempts) {
          await Future<void>.delayed(pollInterval);
        }
      }
    } on Object {
      _setStatus(ActivityCompletionStatus.pollingFailure);
      return false;
    }

    _setStatus(ActivityCompletionStatus.pollingFailure);
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setStatus(ActivityCompletionStatus value) {
    if (_disposed) return;
    status = value;
    notifyListeners();
  }
}
