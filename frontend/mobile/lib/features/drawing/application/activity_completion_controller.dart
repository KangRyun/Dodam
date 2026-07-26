import 'package:flutter/foundation.dart';

import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';

enum ActivityCompletionStatus {
  idle,
  submitting,
  accepted,
  polling,
  completed,
  terminalFailure,
  pollingFailure,
  failure,
}

/// 전체 그림 활동 완료 접수와 비동기 완료 상태 조회를 관리한다.
///
/// 완료 접수 재시도에는 동일한 `Idempotency-Key`를 재사용하며, 접수 후에는
/// Drawing Session이 종단 상태가 될 때까지 제한된 횟수로 조회한다.
final class ActivityCompletionController extends ChangeNotifier {
  ActivityCompletionController(
    this._repository, {
    required this.sessionId,
    required this.conversationSkipped,
    required this.idempotencyKeyProvider,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 30,
  }) : assert(maxPollAttempts > 0);

  /// 이미 접수된 활동의 완료 상태만 조회하는 컨트롤러를 생성한다.
  ActivityCompletionController.forStatus(
    this._repository, {
    required this.sessionId,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 30,
  }) : conversationSkipped = true,
       idempotencyKeyProvider = _unusedIdempotencyKey,
       assert(maxPollAttempts > 0);

  final DrawingRepository _repository;
  final int sessionId;
  final bool conversationSkipped;
  final String Function() idempotencyKeyProvider;
  final Duration pollInterval;
  final int maxPollAttempts;

  ActivityCompletionStatus status = ActivityCompletionStatus.idle;
  String? _pendingIdempotencyKey;
  DrawingCompletionResponseDto? result;

  /// 전체 활동 완료를 접수한다.
  ///
  /// 통신 실패 후 재시도하면 최초 요청에 사용한 멱등 키를 유지한다.
  ///
  /// @return Backend가 완료 요청을 접수했으면 `true`
  Future<bool> submit() async {
    if (status == ActivityCompletionStatus.submitting ||
        status == ActivityCompletionStatus.accepted) {
      return false;
    }
    status = ActivityCompletionStatus.submitting;
    _pendingIdempotencyKey ??= idempotencyKeyProvider();
    notifyListeners();
    try {
      result = await _repository.completeActivity(
        sessionId,
        request: CompleteActivityRequestDto(
          conversationSkipped: conversationSkipped,
        ),
        idempotencyKey: _pendingIdempotencyKey!,
      );
      status = ActivityCompletionStatus.accepted;
      _pendingIdempotencyKey = null;
      notifyListeners();
      return true;
    } on Object {
      status = ActivityCompletionStatus.failure;
      notifyListeners();
      return false;
    }
  }

  /// Drawing Session이 `COMPLETED` 또는 `FAILED`가 될 때까지 조회한다.
  ///
  /// 조회 실패나 제한 횟수 초과는 활동 실패로 단정하지 않고
  /// [ActivityCompletionStatus.pollingFailure]로 구분한다.
  ///
  /// @return 세션이 `COMPLETED` 상태에 도달했으면 `true`
  Future<bool> pollUntilTerminal() async {
    if (status == ActivityCompletionStatus.polling) return false;
    status = ActivityCompletionStatus.polling;
    notifyListeners();

    try {
      for (var attempt = 0; attempt < maxPollAttempts; attempt += 1) {
        final session = await _repository.getSession(sessionId);
        if (session.sessionStatus == 'COMPLETED') {
          status = ActivityCompletionStatus.completed;
          notifyListeners();
          return true;
        }
        if (session.sessionStatus == 'FAILED') {
          status = ActivityCompletionStatus.terminalFailure;
          notifyListeners();
          return false;
        }
        if (attempt + 1 < maxPollAttempts) {
          await Future<void>.delayed(pollInterval);
        }
      }
    } on Object {
      status = ActivityCompletionStatus.pollingFailure;
      notifyListeners();
      return false;
    }

    status = ActivityCompletionStatus.pollingFailure;
    notifyListeners();
    return false;
  }
}

String _unusedIdempotencyKey() => '';
