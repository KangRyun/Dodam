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
    'thumbnailUrl': '/api/v1/drawing-assets/120/file',
    'activityDate': '2026-07-20',
    'durationMs': 1380000,
    'expertReviewAvailable': false,
  };

  /// REPORT-02 보호자 공개 계약(§13.4) + 재구성 계약
  /// (`docs/S15P11B209-875-report-api-contract.md`)과 같은 모양의 개발용 표본.
  /// 서버는 공통 봉투로 감싸 보내지만, DTO가 봉투 없는 본문도 받으므로
  /// 여기서는 `data` 페이로드만 담는다.
  ///
  /// 그림일기 표본이라 §5의 "HTP가 아닌 활동"에 해당해 `subjectReports`가
  /// 한 건(전체 그림)이다. 서버 없이도 §11 섹션 순서를 눈으로 확인할 수 있게
  /// 각 신규 섹션을 한 건씩 채워 뒀다.
  static const _detail = {
    'reportId': 501,
    'reportVersion': 1,
    'reportStatus': 'COMPLETED',
    'activityType': 'ART_DIARY',
    'childDisplayName': '민준',
    'nonDiagnosticNotice':
        '이 리포트는 아이가 그림을 그리고 대화한 과정에서 나타난 특징과 심리적 경향을 정리한 자료입니다. '
        '아이의 평소 성격이나 심리 상태를 확정하거나 진단하는 결과는 아닙니다.',
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
      'finalImageUrl': '/api/v1/drawing-assets/120/file',
      'thumbnailUrl': '/api/v1/drawing-assets/120/file',
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
    'observedFeatures': [
      {
        'title': '가족을 가운데에 그렸어요',
        'description': '종이 가운데에 가족을 크게 그렸어요.',
        'evidenceSummary': '그림에서 확인했어요.',
      },
    ],
    'activityFacts': {
      'detectedObjects': ['사람', '집', '해'],
      'totalDurationSec': 1380,
      'drawingDurationMs': 1320000,
      'drawingDurationSec': 1320,
      'pauseCount': 4,
      'eraseCount': 2,
      'undoCount': 2,
      'questionCount': 5,
      'answerCount': 4,
      'skipCount': 1,
      'detectedElementCount': 3,
      'pressureAvailable': false,
      'truncated': false,
      'aggregatedHtp': false,
      'notes': ['멈춤 4회 관찰'],
    },
    'conversationSummary': {
      'questionCount': 5,
      'answeredCount': 4,
      'skippedCount': 1,
      'summary': '가족과 함께 있는 장면을 이야기하며 편안하게 대화했어요.',
    },
    'publicInterpretations': [
      {
        'category': 'RELATIONSHIP',
        'title': '가족과의 정서적 연결',
        'tendencyText': '가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.',
        'scopeText': '이번 그림 활동에서 나타난 가능성입니다.',
        'homeObservationGuide': '새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.',
        'evidenceRefs': [101, 102],
      },
    ],
    'evidenceItems': [
      {
        'evidenceId': 101,
        'sourceType': 'CHILD_ANSWER',
        'text': '집에는 우리 가족이 산다고 답했어요.',
      },
      {'evidenceId': 102, 'sourceType': 'VISION', 'text': '가족을 서로 가깝게 그렸어요.'},
    ],
    'subjectReports': [
      {
        'subjectType': 'DRAWING',
        'imageUrl': '/api/v1/drawing-assets/120/file',
        'visionObservations': ['가족을 서로 가깝게 그렸어요.'],
        'qaPairs': [
          {
            'question': '이 그림에는 누가 있어요?',
            'answer': '우리 가족이요',
            'state': 'ANSWERED',
            'inputType': 'VOICE',
            'sttNeedsConfirmation': false,
            'isRepresentative': true,
          },
          {
            'question': '해는 왜 그렸어요?',
            'answer': null,
            'state': 'SKIPPED',
            'inputType': 'TEXT',
            'sttNeedsConfirmation': false,
            'isRepresentative': false,
          },
        ],
        'interpretationRefs': [0],
      },
    ],
    'parentGuides': [
      {
        'guideType': 'DRAWING_CONVERSATION',
        'items': ['그림에서 가장 마음에 드는 부분을 아이에게 물어봐 주세요.'],
      },
      {
        'guideType': 'DAILY_PARENTING',
        'items': ['하루 한 번은 아이의 이야기를 끝까지 들어 주세요.'],
      },
      {
        'guideType': 'HOME_OBSERVATION',
        'items': ['새로운 상황에서 아이가 어떻게 반응하는지 살펴봐 주세요.'],
      },
      {
        'guideType': 'PROFESSIONAL_SUPPORT',
        'items': ['더 이야기 나누고 싶을 때는 전문가 상담을 참고할 수 있어요.'],
      },
    ],
    'references': [
      {'title': '아이 그림과 대화 이해하기', 'url': null},
    ],
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
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) async =>
      ReportGenerationStatusDto.fromJson({
        'reportId': reportId,
        'drawingSessionId': 120,
        'analysisId': 15901,
        'reportVersion': 1,
        'reportStatus': 'COMPLETED',
        'retryable': false,
      });

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) async => ReportGenerationStatusDto.fromJson({
    'reportId': reportId + 1,
    'drawingSessionId': 120,
    'analysisId': 15901,
    'reportVersion': 2,
    'reportStatus': 'GENERATING',
    'retryable': false,
  });

  @override
  Future<Uint8List> downloadImage(String imageUrl) async =>
      Uint8List.fromList(const <int>[]);

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
