import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../../conversation/domain/models/conversation_end.dart';
import '../../conversation/domain/repositories/conversation_end_repository.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';

enum DrawingActivityCompletionStatus {
  idle,
  endingConversation,
  savingReflection,
  requestingCompletion,
  accepted,
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
  }) : _conversationResolved = conversationId != null,
       _conversationEndKey = previousConversationEndIdempotencyKey,
       _conversationEndRequest = previousConversationEndRequest;

  final DrawingRepository drawingRepository;
  final ConversationEndRepository? conversationEndRepository;
  final String Function() idempotencyKeyProvider;
  final int sessionId;
  int? conversationId;

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
  CompleteActivityRequestDto? _activityCompleteRequest;
  bool _reflectionSaved = false;
  bool _conversationResolved;
  bool _disposed = false;

  bool get isSubmitting => switch (status) {
    DrawingActivityCompletionStatus.endingConversation ||
    DrawingActivityCompletionStatus.savingReflection ||
    DrawingActivityCompletionStatus.requestingCompletion => true,
    _ => false,
  };
  bool get reflectionInputLocked => _reflectionRequest != null;
  bool get reflectionWasSkipped => _reflectionRequest?.skipped ?? false;

  Future<bool> submit({
    required SaveDrawingReflectionRequestDto reflection,
    required int? lastQuestionMessageId,
  }) async {
    if (isSubmitting || status == DrawingActivityCompletionStatus.accepted) {
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
      return true;
    } on Object catch (failure) {
      error = failure;
      failedStep = status;
      _debugCompletionFailure(status, failure);
      _setStatus(DrawingActivityCompletionStatus.failed);
      return false;
    }
  }

  Future<void> _resolveConversationContext() async {
    if (_conversationResolved) return;
    final detail = await drawingRepository.getSession(sessionId);
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
    _activityCompleteRequest ??= CompleteActivityRequestDto(
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
    if (!_isAcceptedCompletion(response)) {
      throw StateError('Unexpected activity completion result.');
    }
    _setStatus(DrawingActivityCompletionStatus.accepted);
  }

  /// 서버가 완료를 접수했다고 볼 수 있는 응답인지 판정한다.
  ///
  /// 정본 응답은 두 가지다.
  ///
  ///     COMPLETED / COMPLETED     일반 활동. 리포트 생성을 기다리지 않고 그 자리에서
  ///                               끝난다 — 리포트 진행 상태는 `reports` 행이 따로 든다.
  ///     IN_PROGRESS / REPORTING   HTP 묶음. 주제별 세션은 검사 완료까지 접수 상태로 남는다.
  ///
  /// 앞의 것을 빠뜨려 **서버는 성공했는데 앱만 실패로 본** 적이 있다(2026-08-08 실측).
  /// 감정도 저장됐고 완료도 접수됐는데 아이 화면에는 "지금은 잘 안 돼요"가 떴고, 재시도는
  /// 같은 멱등 키로 같은 응답을 받아 영원히 같은 자리에서 막혔다. 그래서 이 판정은
  /// **열어 둔 목록이 아니라 두 정본을 나열한 화이트리스트**로 둔다 — 계약이 또 바뀌면
  /// 조용히 통과하는 대신 여기서 걸려 이 주석까지 읽게 된다.
  bool _isAcceptedCompletion(DrawingCompletionResponseDto response) {
    final finished =
        response.sessionStatus == 'COMPLETED' &&
        response.currentStage == 'COMPLETED';
    final reporting =
        response.sessionStatus == 'IN_PROGRESS' &&
        response.currentStage == 'REPORTING';
    return finished || reporting;
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

/// 완료 흐름의 실패를 디버그 빌드에서만 한 줄로 남긴다.
///
/// 아이 화면 문구는 두 가지뿐이라(연결이냐 아니냐) 화면만 봐서는 401 인지 400 인지 계약
/// 불일치인지 구분할 수 없다. 그림 완료 경로에는 같은 로그가 이미 있는데 이 경로에만 없어서,
/// **서버가 성공한 실패**를 서버 로그 없이는 짚지 못했다(2026-08-08).
///
/// 아이 발화·제목·감정 값은 남기지 않는다 — 어느 단계에서 어떤 코드로 끊겼는지만 남긴다.
void _debugCompletionFailure(
  DrawingActivityCompletionStatus step,
  Object failure,
) {
  if (!kDebugMode) return;
  final where = 'step=${step.name}';
  switch (failure) {
    case ApiResponseFailure(:final statusCode, :final error):
      debugPrint(
        '[ACTIVITY_COMPLETE] http_failure $where '
        'status=${statusCode ?? 'unknown'} code=${error?.code ?? 'unknown'}',
      );
    case ApiTransportFailure(:final type):
      debugPrint(
        '[ACTIVITY_COMPLETE] transport_failure $where '
        'transportType=${type.name}',
      );
    default:
      debugPrint(
        '[ACTIVITY_COMPLETE] failure $where '
        'exceptionType=${failure.runtimeType}',
      );
  }
}
