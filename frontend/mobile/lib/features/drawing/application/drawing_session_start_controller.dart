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

  Future<DrawingSessionResolution> resolveSession({
    required int childId,
  }) async {
    final activeSession = await repository.getActiveSession(childId);
    if (activeSession != null) {
      return DrawingSessionResolution(
        sessionId: activeSession.drawingSessionId,
        currentStage: activeSession.currentStage,
      );
    }

    final drawingTypes = await repository.getDrawingTypes(childId: childId);
    if (drawingTypes.content.isEmpty) {
      throw StateError('No selectable drawing type is available.');
    }
    final sortedTypes = [...drawingTypes.content]
      ..sort((left, right) => left.displayOrder.compareTo(right.displayOrder));

    try {
      final session = await repository.createSession(
        CreateDrawingSessionRequestDto(
          childId: childId,
          drawingTypeId: sortedTypes.first.drawingTypeId,
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
