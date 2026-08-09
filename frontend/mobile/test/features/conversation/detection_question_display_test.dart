import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('객체 탐지 성공 후 분석 ID로 질문을 요청해 화면에 표시한다', (tester) async {
    final repository = _ConversationRepository();
    final detectionController = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 1),
      saveDraft: () async => const DraftSaveResponseDto(
        drawingAssetId: 120,
        assetVersion: 1,
        lastEventSequence: 1,
        savedAt: '2026-07-24T00:00:00Z',
        expiresAt: null,
      ),
      requestDetection: (_) async => _detection,
    );
    addTearDown(detectionController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          childId: '1',
          objectDetectionController: detectionController,
          conversationRepository: repository,
          conversationId: 8001,
        ),
      ),
    );

    detectionController.onDrawingInputStarted();
    detectionController.onDrawingInputEnded();
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    await tester.pump();

    expect(repository.requestedAnalysisIds, [7001]);
    expect(find.text('이 집에는 누가 살고 있어?'), findsOneWidget);
  });

  testWidgets('HTP 그리기 중 객체 탐지 성공은 질문을 시작하지 않는다', (tester) async {
    final repository = _ConversationRepository();
    final detectionController = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 1),
      saveDraft: () async => const DraftSaveResponseDto(
        drawingAssetId: 120,
        assetVersion: 1,
        lastEventSequence: 1,
        savedAt: '2026-07-24T00:00:00Z',
        expiresAt: null,
      ),
      requestDetection: (_) async => _detection,
    );
    addTearDown(detectionController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          childId: '1',
          objectDetectionController: detectionController,
          conversationRepository: repository,
          conversationId: 8001,
          activityContext: const DrawingActivityContextDto(
            activityKind: 'HTP',
            htpAssessmentId: 91,
            htpStatus: 'IN_PROGRESS',
            stepOrder: 1,
            drawingSubject: 'HOUSE',
          ),
        ),
      ),
    );

    detectionController.onDrawingInputStarted();
    detectionController.onDrawingInputEnded();
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();

    expect(repository.requestedAnalysisIds, isEmpty);
    expect(find.text('이 집에는 누가 살고 있어?'), findsNothing);
  });
}

final class _ConversationRepository implements ConversationRepository {
  final List<int?> requestedAnalysisIds = [];

  @override
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async => const ConversationStartResult(
    conversationId: 8001,
    maxQuestionCount: 5,
  );

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    requestedAnalysisIds.add(request.basisAnalysisId);
    return AiQuestion(
      messageId: 9001,
      conversationId: conversationId,
      sequence: 1,
      text: '이 집에는 누가 살고 있어?',
      options: const [],
      ttsAvailable: false,
      createdAt: DateTime(2026, 7, 24),
    );
  }
}

const _detection = ObjectDetectionResponseDto(
  drawingAnalysisId: 7001,
  drawingSessionId: 481,
  drawingAssetId: 120,
  requestId: 'preview-detection',
  analysisType: 'OBJECT_DETECTION',
  status: 'SUCCEEDED',
  model: DrawingAnalysisModelDto(name: 'preview', version: '1.0'),
  detections: [],
  requestedAt: '2026-07-24T00:00:00Z',
  processedAt: '2026-07-24T00:00:01Z',
);
