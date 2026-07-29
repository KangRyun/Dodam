import 'package:dodam/features/drawing/application/htp_response_flow_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('집 대화 완료 후 CANVAS 방식의 나무 세션을 반환한다', () async {
    final repository = _HtpRepository(
      response: _assessment(stepOrder: 2, subject: 'TREE', sessionId: 43),
    );

    final result = await HtpResponseFlowController(
      repository,
    ).moveToNextCanvas(91);

    expect(repository.assessmentId, 91);
    expect(repository.inputMethod, 'CANVAS');
    expect(result.allStepsCompleted, isFalse);
    expect(result.nextSession?.sessionId, 43);
    expect(result.nextSession?.currentStage, 'DRAWING');
    expect(result.nextSession?.activityContext.drawingSubject, 'TREE');
    expect(result.nextSession?.activityContext.stepOrder, 2);
  });

  test('사람 대화 완료 후 모든 단계 완료 결과를 반환한다', () async {
    final repository = _HtpRepository(
      response: _assessment(
        stepOrder: 3,
        subject: 'PERSON',
        sessionId: 44,
        allStepsCompleted: true,
      ),
    );

    final result = await HtpResponseFlowController(
      repository,
    ).moveToNextCanvas(91);

    expect(repository.inputMethod, 'CANVAS');
    expect(result.allStepsCompleted, isTrue);
    expect(result.nextSession, isNull);
  });
}

HtpAssessmentDto _assessment({
  required int stepOrder,
  required String subject,
  required int sessionId,
  bool allStepsCompleted = false,
}) => HtpAssessmentDto(
  htpAssessmentId: 91,
  status: 'IN_PROGRESS',
  expiresAt: '2026-08-01T00:00:00Z',
  currentStep: HtpAssessmentStepDto(
    stepOrder: stepOrder,
    drawingSubject: subject,
    drawingSessionId: sessionId,
    sessionStatus: 'IN_PROGRESS',
    currentStage: 'DRAWING',
  ),
  allStepsCompleted: allStepsCompleted,
);

final class _HtpRepository implements HtpDrawingRepository {
  _HtpRepository({required this.response});

  final HtpAssessmentDto response;
  int? assessmentId;
  String? inputMethod;

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
  }) async {
    this.assessmentId = assessmentId;
    this.inputMethod = inputMethod;
    return response;
  }

  @override
  Future<void> completeHtpAssessment(int assessmentId) =>
      throw UnimplementedError();

  @override
  Future<HtpAssessmentDto> getHtpAssessment(int assessmentId) =>
      throw UnimplementedError();

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) => throw UnimplementedError();
}
