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
    'drawingType': {'code': 'ART_DIARY', 'name': '그림일기'},
    'inputMethod': 'CANVAS',
    'selectedEmotions': ['JOY', 'UNSURE'],
    'thumbnailUrl': 'https://storage.i15b209.example/previews/ds120-v1.png',
    'isExpertReviewRecommended': false,
    'createdAt': '2026-07-20T10:12:00Z',
  };
  static const _detail = {
    'reportId': 501,
    'drawingSessionId': 120,
    'analysisId': 88,
    'reportVersion': 1,
    'reportStatus': 'COMPLETED',
    'activitySummary': {
      'title': '우리 가족',
      'drawingType': {'code': 'ART_DIARY', 'name': '그림일기'},
      'inputMethod': 'CANVAS',
      'startedAt': '2026-07-20T09:40:00Z',
      'completedAt': '2026-07-20T10:03:00Z',
      'durationMinutes': 23,
      'selectedEmotions': ['JOY', 'UNSURE'],
    },
    'drawingImageUrl': 'https://storage.i15b209.example/final/ds120-v2.png',
    'observedFeatures': [
      {
        'label': '가족을 화면 가운데에 크게 그렸어요',
        'description': '네 명의 인물을 캔버스 중앙에 배치하고 따뜻한 색을 주로 사용했어요.',
        'evidenceRef': 'OBJ_PERSON_1',
      },
    ],
    'keyConversations': [
      {
        'question': '이 사람은 누구야?',
        'answer': '우리 동생이야. 같이 노는 거야.',
        'answerType': 'VOICE',
      },
    ],
    'evidence': {
      'drawingRefs': ['OBJ_PERSON_1', 'OBJ_SUN_1'],
      'conversationRefs': [3021],
    },
    'followUp': {
      'attentionPoints': ['동생 이야기를 할 때 목소리가 작아지는 모습이 있었어요.'],
      'guidance': '그림을 함께 보며 열린 질문으로 시작해 보세요.',
    },
    'guardianQuestions': ['오늘 그린 그림에서 제일 좋아하는 부분은 어디야?'],
    'isExpertReviewRecommended': false,
    'limitationsText': '이 리포트는 의료적·심리학적 진단이 아니며, 아이와의 대화를 돕기 위한 관찰 참고 자료입니다.',
    'modelVersion': 'dodam-report-v1.2',
    'createdAt': '2026-07-20T10:12:00Z',
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
