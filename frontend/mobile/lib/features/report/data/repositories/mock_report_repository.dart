import 'dart:typed_data';

import '../../../../core/network/api_page.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../domain/repositories/report_repository.dart';
import '../dto/report_dtos.dart';

final class MockReportRepository implements ReportRepository {
  const MockReportRepository();
  static const _summary = {
    'reportId': 501,
    'drawingSessionId': 120,
    'reportVersion': 1,
    'reportStatus': 'COMPLETED',
    'title': '우리 가족',
    'drawingType': {'drawingTypeId': 7, 'code': 'ART_DIARY', 'name': '그림일기'},
    'selectedEmotions': ['JOY', 'UNSURE'],
    'thumbnailUrl': 'https://storage.i15b209.example/previews/ds120-v1.png',
    'activityDate': '2026-07-20',
    'durationMs': 1380000,
    'expertReviewAvailable': false,
  };

  /// REPORT-02 보호자 공개 계약(§13.4)과 같은 모양의 개발용 표본.
  /// 서버는 공통 봉투로 감싸 보내지만, DTO가 봉투 없는 본문도 받으므로
  /// 여기서는 `data` 페이로드만 담는다.
  static const _detail = {
    'reportId': 501,
    'reportVersion': 1,
    'reportStatus': 'COMPLETED',
    'drawingSession': {
      'drawingSessionId': 120,
      'childId': 3,
      'drawingTypeCode': 'ART_DIARY',
      'drawingTypeName': '그림일기',
      'title': '우리 가족',
      'inputMethod': 'CANVAS',
      'startedAt': '2026-07-20T09:40:00',
      'completedAt': '2026-07-20T10:03:00',
      'durationMs': 1380000,
    },
    'drawing': {
      'finalImageUrl': 'https://storage.i15b209.example/final/ds120-v2.png',
      'thumbnailUrl': 'https://storage.i15b209.example/previews/ds120-v1.png',
    },
    'childExpression': {
      'selectedEmotions': ['JOY', 'UNSURE'],
      'expressedEmotionText': '동생이랑 놀아서 좋았어요',
      'representativeUtterances': [
        {
          'messageId': 804,
          'text': '우리 동생이야. 같이 노는 거야.',
          'source': 'STT',
          'sttNeedsConfirmation': false,
        },
        {
          'messageId': 805,
          'text': '해도 같이 그렸어.',
          'source': 'TEXT',
          'sttNeedsConfirmation': false,
        },
      ],
    },
    'activityFacts': {
      'detectedObjects': ['사람', '집', '해'],
      'drawingDurationMs': 1320000,
      'pauseCount': 4,
      'eraseCount': 2,
      'pressureAvailable': false,
      'notes': ['멈춤 4회 관찰'],
    },
    'conversationSummary': {
      'questionCount': 5,
      'answeredCount': 4,
      'skippedCount': 1,
      'summary': '가족과 함께 있는 장면을 이야기하며 편안하게 대화했어요.',
    },
    'guardianConversationGuide': ['오늘 그린 그림에서 제일 좋아하는 부분은 어디야?'],
    'limitations': ['이 리포트는 의료적·심리학적 진단이 아니며, 아이와의 대화를 돕기 위한 관찰 참고 자료입니다.'],
    'expertReview': {'status': 'NOT_REQUESTED', 'available': false},
    'createdAt': '2026-07-20T10:12:00',
  };
  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) async => ApiPage(
    content: [ReportSummaryDto.fromJson(_summary)],
    page: 0,
    size: 20,
    totalElements: 1,
    totalPages: 1,
    hasNext: false,
  );
  @override
  Future<ReportDetailDto> getReport(int reportId) async =>
      ReportDetailDto.fromJson(_detail);

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) async => ReportExportDto(
    reportId: reportId,
    exportId: reportId,
    status: 'COMPLETED',
    downloadUrl: '/api/v1/reports/$reportId/exports/$reportId/file',
  );

  @override
  Future<Uint8List> downloadExport(String downloadUrl) async =>
      Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) async =>
      AnalysisStatusDto.fromJson(const {
        'analysisId': 15901,
        'analysisType': 'FINAL',
        'analysisStatus': 'COMPLETED',
        'confidence': 0.86,
        'modelVersion': '2026.07.1',
        'visualFeatures': {'canvasCoverageRatio': 0.62},
        'behaviorFeatures': {'inputMethod': 'CANVAS', 'strokeCount': 214},
        'conversationSummary': {'summaryText': '가족과 함께 있는 집을 그리며 이야기를 나눴어요.'},
        'observationResult': {
          'overallSummary': '밝은 색을 넓게 사용하며 가족을 중심으로 그렸어요.',
          'observedEmotion': 'JOY',
          'emotionConfidence': 0.82,
          'positiveSignals': '가족 이야기에 적극적으로 응답했어요.',
          'attentionPoints': '다음에는 아이가 직접 골라 그리도록 해보세요.',
          'guardianGuidance': '오늘 그린 집에 대해 함께 이야기 나눠보세요.',
          'isExpertReviewRequired': false,
          'disclaimerText': '이 결과는 의료적 진단이 아니라 관찰 참고 자료입니다.',
        },
      });
  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) async => AnalysisAcceptedDto.fromJson(const {
    'analysisId': 15990,
    'retryOfAnalysisId': 15901,
    'analysisType': 'FINAL',
    'analysisStatus': 'PENDING',
    'requestedAt': '2026-07-21T10:02:33Z',
  });
}
