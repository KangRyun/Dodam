import '../../../core/network/network.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';

typedef DrawingSessionStartClock = DateTime Function();

final class DrawingSessionStartController {
  DrawingSessionStartController({
    required this.repository,
    DrawingSessionStartClock? now,
  }) : _now = now ?? DateTime.now;

  final DrawingRepository repository;
  final DrawingSessionStartClock _now;

  Future<int> resolveSession({required int childId}) async {
    final activeSession = await repository.getActiveSession(childId);
    if (activeSession != null) return activeSession.drawingSessionId;

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
      return session.drawingSessionId;
    } on ApiResponseFailure catch (failure) {
      if (failure.error?.code != 'DRAWING_409_001') rethrow;
      final racedSession = await repository.getActiveSession(childId);
      if (racedSession == null) rethrow;
      return racedSession.drawingSessionId;
    }
  }
}
