import 'package:flutter/foundation.dart';

import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';

enum ActivityCompletionStatus { idle, submitting, accepted, failure }

final class ActivityCompletionController extends ChangeNotifier {
  ActivityCompletionController(
    this._repository, {
    required this.sessionId,
    required this.conversationSkipped,
    required this.idempotencyKeyProvider,
  });

  final DrawingRepository _repository;
  final int sessionId;
  final bool conversationSkipped;
  final String Function() idempotencyKeyProvider;

  ActivityCompletionStatus status = ActivityCompletionStatus.idle;
  String? _pendingIdempotencyKey;
  DrawingCompletionResponseDto? result;

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
}
