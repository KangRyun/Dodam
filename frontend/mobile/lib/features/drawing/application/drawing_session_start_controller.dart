import '../../../core/network/network.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';

typedef DrawingSessionStartClock = DateTime Function();

/// 활동을 이어갈 세션과 그 세션이 머문 단계를 함께 전달한다.
///
/// 진행 중 세션은 그림 단계를 이미 지난 상태일 수 있어(대화·회고) 호출부가 단계에
/// 맞는 화면으로 복귀할 수 있도록 `currentStage`를 함께 반환한다.
final class DrawingSessionResolution {
  const DrawingSessionResolution({
    required this.sessionId,
    required this.currentStage,
  });

  final int sessionId;
  final String currentStage;

  /// 그림 저장·획 전송이 허용되는 단계인지 나타낸다.
  bool get isDrawingStage => currentStage == 'DRAWING';
}

final class DrawingSessionStartController {
  DrawingSessionStartController({
    required this.repository,
    DrawingSessionStartClock? now,
  }) : _now = now ?? DateTime.now;

  final DrawingRepository repository;
  final DrawingSessionStartClock _now;

  Future<ActiveDrawingSessionDto?> findActiveSession({required int childId}) =>
      repository.getActiveSession(childId);

  /// 임시 저장본이나 그림 완료 결과가 있으면 사용자에게 시작 방식을 묻는다.
  bool hasSavedDrawing(ActiveDrawingSessionDto session) =>
      session.latestDraft != null || session.currentStage != 'DRAWING';

  DrawingSessionResolution resume(ActiveDrawingSessionDto session) =>
      DrawingSessionResolution(
        sessionId: session.drawingSessionId,
        currentStage: session.currentStage,
      );

  Future<DrawingSessionResolution> resolveSession({
    required int childId,
    int? drawingTypeId,
  }) async {
    final activeSession = await findActiveSession(childId: childId);
    if (activeSession != null) {
      return resume(activeSession);
    }

    return createNewSession(childId: childId, drawingTypeId: drawingTypeId);
  }

  /// 기존 활동을 폐기한 뒤 새 그림 세션을 만든다.
  Future<DrawingSessionResolution> replaceActiveSession({
    required int childId,
    required int activeSessionId,
    int? drawingTypeId,
  }) async {
    await discardActiveSession(activeSessionId);
    return createNewSession(childId: childId, drawingTypeId: drawingTypeId);
  }

  /// 임시 그림만 삭제하고 현재 화면에 머문다.
  Future<void> discardActiveSession(int activeSessionId) async {
    if (repository is! DrawingSessionDiscarder) {
      throw UnsupportedError('Drawing session deletion is unavailable.');
    }
    final discarder = repository as DrawingSessionDiscarder;
    await discarder.deleteSession(activeSessionId);
  }

  Future<DrawingSessionResolution> createNewSession({
    required int childId,
    int? drawingTypeId,
  }) async {
    final drawingTypes = await repository.getDrawingTypes(childId: childId);
    if (drawingTypes.content.isEmpty) {
      throw StateError('No selectable drawing type is available.');
    }
    final sortedTypes = [...drawingTypes.content]
      ..sort((left, right) => left.displayOrder.compareTo(right.displayOrder));
    // 홈 카드에서 고른 활동 유형을 우선 사용하고, 지정되지 않았거나 더 이상
    // 선택 가능한 목록에 없으면 첫 번째 유형으로 되돌아간다.
    final resolvedTypeId = sortedTypes
        .firstWhere(
          (type) => type.drawingTypeId == drawingTypeId,
          orElse: () => sortedTypes.first,
        )
        .drawingTypeId;

    try {
      final session = await repository.createSession(
        CreateDrawingSessionRequestDto(
          childId: childId,
          drawingTypeId: resolvedTypeId,
          inputMethod: 'CANVAS',
          clientStartedAt: _now().toUtc().toIso8601String(),
        ),
      );
      return DrawingSessionResolution(
        sessionId: session.drawingSessionId,
        currentStage: session.currentStage,
      );
    } on ApiResponseFailure catch (failure) {
      if (failure.error?.code != 'DRAWING_409_001') rethrow;
      final racedSession = await repository.getActiveSession(childId);
      if (racedSession == null) rethrow;
      return DrawingSessionResolution(
        sessionId: racedSession.drawingSessionId,
        currentStage: racedSession.currentStage,
      );
    }
  }
}
