import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../../conversation/domain/models/conversation_end.dart';
import '../../conversation/domain/repositories/conversation_end_repository.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';

typedef DrawingCompletionDelay = Future<void> Function(Duration duration);

enum DrawingActivityCompletionStatus {
  idle,
  endingConversation,
  savingReflection,
  requestingCompletion,
  reporting,
  completed,
  failed,
}

final class DrawingActivityCompletionController extends ChangeNotifier {
  DrawingActivityCompletionController({
    required this.drawingRepository,
    required this.sessionId,
    required this.conversationId,
    required this.conversationAlreadyEnded,
    required this.conversationEndRepository,
    required this.idempotencyKeyProvider,
    String? previousConversationEndIdempotencyKey,
    ConversationEndRequest? previousConversationEndRequest,
    DrawingCompletionDelay? delay,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPollAttempts = 60,
    this.maxTransientPollRetries = 3,
    this.transientPollBackoff = const Duration(seconds: 1),
  }) : _delay = delay ?? Future<void>.delayed,
       _conversationResolved = conversationId != null,
       _conversationEndKey = previousConversationEndIdempotencyKey,
       _conversationEndRequest = previousConversationEndRequest;

  final DrawingRepository drawingRepository;
  final ConversationEndRepository? conversationEndRepository;
  final String Function() idempotencyKeyProvider;
  final DrawingCompletionDelay _delay;
  final int sessionId;
  int? conversationId;
  final Duration pollInterval;
  final int maxPollAttempts;
  final int maxTransientPollRetries;
  final Duration transientPollBackoff;

  DrawingActivityCompletionStatus status = DrawingActivityCompletionStatus.idle;
  bool conversationAlreadyEnded;
  Object? error;
  DrawingActivityCompletionStatus? failedStep;
  int? analysisId;
  String? analysisStatus;
  int? reportId;

  String? _conversationEndKey;
  String? _activityCompleteKey;
  ConversationEndRequest? _conversationEndRequest;
  SaveDrawingReflectionRequestDto? _reflectionRequest;
  DrawingActivityCompleteRequestDto? _activityCompleteRequest;
  bool _reflectionSaved = false;
  bool _conversationResolved;
  bool _disposed = false;

  bool get isSubmitting => switch (status) {
    DrawingActivityCompletionStatus.endingConversation ||
    DrawingActivityCompletionStatus.savingReflection ||
    DrawingActivityCompletionStatus.requestingCompletion ||
    DrawingActivityCompletionStatus.reporting => true,
    _ => false,
  };
  bool get reflectionInputLocked => _reflectionRequest != null;
  bool get reflectionWasSkipped => _reflectionRequest?.skipped ?? false;

  Future<bool> submit({
    required SaveDrawingReflectionRequestDto reflection,
    required int? lastQuestionMessageId,
  }) async {
    if (isSubmitting || status == DrawingActivityCompletionStatus.completed) {
      return false;
    }
    error = null;
    failedStep = null;
    try {
      await _resolveConversationContext();
      if (_disposed) return false;
      await _endConversationIfNeeded(lastQuestionMessageId);
      if (_disposed) return false;
      await _saveReflectionIfNeeded(reflection);
      if (_disposed) return false;
      await _requestActivityCompletion();
      if (_disposed) return false;
      return await _pollUntilTerminal();
    } on Object catch (failure) {
      error = failure;
      failedStep = status;
      _setStatus(DrawingActivityCompletionStatus.failed);
      return false;
    }
  }

  Future<void> _resolveConversationContext() async {
    if (_conversationResolved) return;
    final detail = await drawingRepository.getSessionCompletionStatus(
      sessionId,
    );
    conversationId = detail.conversationId;
    if (conversationId != null &&
        detail.currentStage != 'CONVERSING' &&
        detail.currentStage != 'DRAWING' &&
        detail.currentStage != 'ANALYZING') {
      conversationAlreadyEnded = true;
    }
    _conversationResolved = true;
  }

  Future<void> _endConversationIfNeeded(int? lastQuestionMessageId) async {
    final id = conversationId;
    if (id == null || conversationAlreadyEnded) return;
    final repository = conversationEndRepository;
    if (repository == null) {
      throw StateError('ConversationEndRepository is required.');
    }
    _setStatus(DrawingActivityCompletionStatus.endingConversation);
    _conversationEndRequest ??= ConversationEndRequest(
      reason: ConversationEndReason.childRequest,
      lastQuestionMessageId: lastQuestionMessageId,
    );
    _conversationEndKey ??= _nextDistinctIdempotencyKey();
    final result = await repository.endConversation(
      conversationId: id,
      request: _conversationEndRequest!,
      idempotencyKey: _conversationEndKey!,
    );
    if (result.conversationId != id ||
        !result.completed ||
        result.conversationStatus != 'COMPLETED' ||
        result.nextStage != 'REFLECTION') {
      throw StateError('Unexpected conversation end result.');
    }
    conversationAlreadyEnded = true;
  }

  Future<void> _saveReflectionIfNeeded(
    SaveDrawingReflectionRequestDto reflection,
  ) async {
    if (_reflectionSaved) return;
    _setStatus(DrawingActivityCompletionStatus.savingReflection);
    _reflectionRequest ??= reflection;
    try {
      await drawingRepository.saveReflection(sessionId, _reflectionRequest!);
      _reflectionSaved = true;
    } on ApiResponseFailure catch (failure) {
      if (failure.statusCode == 400 || failure.statusCode == 415) {
        _reflectionRequest = null;
      }
      rethrow;
    }
  }

  Future<void> _requestActivityCompletion() async {
    _setStatus(DrawingActivityCompletionStatus.requestingCompletion);
    _activityCompleteRequest ??= DrawingActivityCompleteRequestDto(
      conversationSkipped: conversationId == null,
    );
    _activityCompleteKey ??= _nextDistinctIdempotencyKey();
    final response = await drawingRepository.completeActivity(
      sessionId,
      request: _activityCompleteRequest!,
      idempotencyKey: _activityCompleteKey!,
    );
    analysisId = response.analysisId;
    analysisStatus = response.analysisStatus;
    reportId = response.reportId;
    if (response.sessionStatus == 'COMPLETED' &&
        response.currentStage == 'COMPLETED') {
      _setStatus(DrawingActivityCompletionStatus.completed);
      return;
    }
    if (response.sessionStatus != 'IN_PROGRESS' ||
        response.currentStage != 'REPORTING') {
      throw StateError('Unexpected activity completion result.');
    }
    _setStatus(DrawingActivityCompletionStatus.reporting);
  }

  Future<bool> _pollUntilTerminal() async {
    if (status == DrawingActivityCompletionStatus.completed) return true;
    var transientRetries = 0;
    for (var attempt = 0; attempt < maxPollAttempts; attempt += 1) {
      if (!await _waitWhileActive(pollInterval)) return false;
      late DrawingSessionCompletionStatusDto detail;
      while (true) {
        if (_disposed) return false;
        try {
          detail = await drawingRepository.getSessionCompletionStatus(
            sessionId,
          );
          break;
        } on Object catch (failure) {
          if (!_isTransientPollingFailure(failure) ||
              transientRetries >= maxTransientPollRetries) {
            rethrow;
          }
          final backoff = transientPollBackoff * (1 << transientRetries);
          transientRetries += 1;
          if (!await _waitWhileActive(backoff)) return false;
        }
      }
      if (_disposed) return false;
      analysisId = detail.latestAnalysis?.drawingAnalysisId;
      analysisStatus = detail.latestAnalysis?.analysisStatus;
      reportId = detail.reportId;
      if (detail.sessionStatus == 'COMPLETED' &&
          detail.currentStage == 'COMPLETED') {
        _setStatus(DrawingActivityCompletionStatus.completed);
        return true;
      }
      if (detail.sessionStatus == 'FAILED') {
        throw StateError('Drawing activity completion failed.');
      }
      if (detail.sessionStatus != 'IN_PROGRESS' ||
          detail.currentStage != 'REPORTING') {
        throw StateError('Unexpected drawing session completion status.');
      }
      _setStatus(DrawingActivityCompletionStatus.reporting);
    }
    throw StateError('Drawing activity completion polling timed out.');
  }

  bool _isTransientPollingFailure(Object failure) => switch (failure) {
    ApiTransportFailure() => true,
    ApiResponseFailure(statusCode: final statusCode?) =>
      statusCode == 408 ||
          statusCode == 429 ||
          (statusCode >= 500 && statusCode < 600),
    _ => false,
  };

  Future<bool> _waitWhileActive(Duration duration) async {
    if (_disposed) return false;
    if (duration > Duration.zero) await _delay(duration);
    return !_disposed;
  }

  String _nextDistinctIdempotencyKey() {
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final candidate = idempotencyKeyProvider();
      if (candidate.length >= 8 &&
          candidate.length <= 100 &&
          candidate != _conversationEndKey &&
          candidate != _activityCompleteKey) {
        return candidate;
      }
    }
    throw StateError('Could not create a distinct Idempotency-Key.');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setStatus(DrawingActivityCompletionStatus value) {
    status = value;
    if (!_disposed) notifyListeners();
  }
}
