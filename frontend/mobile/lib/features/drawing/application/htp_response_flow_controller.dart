import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';
import 'drawing_session_start_controller.dart';

final class HtpResponseFlowResult {
  const HtpResponseFlowResult._({
    required this.allStepsCompleted,
    this.nextSession,
  });

  const HtpResponseFlowResult.completed() : this._(allStepsCompleted: true);

  const HtpResponseFlowResult.next(DrawingSessionResolution nextSession)
    : this._(allStepsCompleted: false, nextSession: nextSession);

  final bool allStepsCompleted;
  final DrawingSessionResolution? nextSession;
}

// HTP 주제별 대화 완료 후 다음 CANVAS 세션을 준비
final class HtpResponseFlowController {
  const HtpResponseFlowController(this._repository);

  final HtpDrawingRepository _repository;

  Future<HtpResponseFlowResult> moveToNextCanvas(int assessmentId) async {
    final assessment = await _repository.moveToNextHtpStep(
      assessmentId,
      inputMethod: 'CANVAS',
    );
    if (assessment.allStepsCompleted) {
      return const HtpResponseFlowResult.completed();
    }

    final step = assessment.currentStep;
    return HtpResponseFlowResult.next(
      DrawingSessionResolution(
        sessionId: step.drawingSessionId,
        currentStage: step.currentStage,
        activityContext: DrawingActivityContextDto(
          activityKind: 'HTP',
          htpAssessmentId: assessment.htpAssessmentId,
          htpStatus: assessment.status,
          stepOrder: step.stepOrder,
          drawingSubject: step.drawingSubject,
        ),
      ),
    );
  }
}
