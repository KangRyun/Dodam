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

// HTP 주제별 대화 완료 후 다음 그림 세션을 준비
final class HtpResponseFlowController {
  const HtpResponseFlowController(this._repository);

  final HtpDrawingRepository _repository;

  /// 현재 끝난 주제와 같은 입력 방식(`inputMethod`)으로 다음 주제 세션을 연다.
  ///
  /// `idempotencyKey`는 호출부가 소유한다 — 같은 전환 재시도는 같은 Key를,
  /// 새로운 전환은 새 Key를 넘겨야 한다.
  Future<HtpResponseFlowResult> moveToNextStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    final assessment = await _repository.moveToNextHtpStep(
      assessmentId,
      inputMethod: inputMethod,
      idempotencyKey: idempotencyKey,
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
        inputMethod: inputMethod,
      ),
    );
  }
}
