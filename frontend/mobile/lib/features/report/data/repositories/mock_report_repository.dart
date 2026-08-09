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

  // HTP 리포트 개발 표본(요약). 그림일기(ART_DIARY)와 나란히 두 번째 기록으로
  // 두어, 서버 없이도 HTP 리포트 UI(집·나무·사람)를 열어볼 수 있게 한다.
  static const _htpSummary = {
    'reportId': 502,
    'drawingSessionId': 121,
    'reportVersion': 1,
    'reportStatus': 'COMPLETED',
    'title': '집·나무·사람 이야기',
    'drawingType': {'drawingTypeId': 1, 'code': 'HTP', 'name': '집-나무-사람'},
    'selectedEmotions': ['JOY'],
    'thumbnailUrl': '/api/v1/drawing-assets/121/file',
    'activityDate': '2026-07-22',
    'durationMs': 1500000,
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
        // 아이 발화(101)가 직접 뒷받침하므로 서버가 STRONG 으로 계산한 카드다.
        'confidence': 'STRONG',
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
    // 그림일기 리포트 V2(diaryInsights) 개발 표본. 값이 있으면 리포트 화면이
    // 아이 이야기 중심 V2 본문을 쓴다(없으면 위 기존 섹션을 그대로 쓴다).
    'diaryInsights': {
      'storySnapshot': {
        'headline': '동생이랑 같이 노는 우리 가족을 그렸어요',
        'summary': '가족이 함께 있는 그림을 그리며, 동생과 노는 게 좋다고 이야기했어요. '
            '해도 같이 그려 넣었어요.',
        'realityStatus': 'REAL',
        'timeScope': 'TODAY',
        'mainEvent': '동생과 함께 놀았다',
      },
      'narrativeFlow': [
        {'stepType': 'EVENT', 'text': '가족이 함께 있는 모습을 그렸어요.'},
        {'stepType': 'CHILD_ACTION', 'text': '동생을 가장 가까이에 그렸어요.'},
        {'stepType': 'EMOTION', 'text': '동생이랑 노는 게 좋다고 했어요.'},
      ],
      'childVoiceItems': [
        {
          'text': '우리 동생이야. 같이 노는 거야.',
          'elicitationType': 'OPEN_INVITATION',
          'sttNeedsConfirmation': false,
        },
        {
          'text': '해도 같이 그렸어.',
          'elicitationType': 'CUED_INVITATION',
          'sttNeedsConfirmation': false,
        },
      ],
      'sessionObservations': [
        {
          'title': '가족을 서로 가깝게 그렸어요',
          'description': '가족을 가운데에 모아 가깝게 배치해 그렸어요.',
          'scopeText': '이번 활동에서 보인 모습이에요. 아이의 지속적인 성향으로 단정하지 말아 주세요.',
        },
      ],
      'caregiverQuestions': [
        {
          'question': '동생이랑 뭐 하고 놀 때가 제일 재밌어?',
          'purpose': '아이가 즐거웠던 순간을 스스로 더 이야기해 볼 수 있어요.',
          'connectionType': 'SHARED_JOY',
          'responseGuide': '아이가 신났던 순간을 말하면 "우와, 정말 신났겠다!" 하고 그 기쁨을 같이 키워 주세요. '
              '함께 기뻐해 준 경험은 아이가 좋은 마음을 더 나누고 싶게 만들어요.',
          'coRegulationAction': '그 즐거웠던 순간을 하나 더 그림에 더해 볼까요?',
          'evidenceRefs': [
            {'kind': 'QA_ANSWER', 'id': '804'},
          ],
        },
        {
          'question': '가족이랑 같이 있을 때 마음이 어땠어?',
          'purpose': '함께 있을 때의 마음을 아이 말로 들어보기',
          'connectionType': 'FEELING_SHARING',
          'responseGuide': '아이가 말하면 먼저 "그랬구나, 그런 마음이었구나" 하고 마음을 그대로 받아 주세요. '
              '옳고 그름을 판단하거나 해결책을 주기보다, 그 마음을 함께 느껴 주는 것으로 충분해요.',
          'coRegulationAction': '그때 마음을 색이나 표정으로 같이 그려 볼까요?',
          'evidenceRefs': [
            {'kind': 'QA_ANSWER', 'id': '805'},
          ],
        },
      ],
      'listeningTip': '그림 속 가족을 설명할 때 누구인지 먼저 물어봐 주면 아이가 자기 이야기를 '
          '이어 가기 쉬워요.',
    },
    'createdAt': '2026-07-20T10:12:00',
  };

  // HTP 리포트 개발 표본(상세). activityType='HTP' 라서 리포트 화면이 HTP
  // 가지로 분기해 집·나무·사람 세 주제를 "그림 이야기" 장(chapter)으로 보여 준다.
  // 주제별 subjectReports(HOUSE/TREE/PERSON) 3건을 채워 세 장이 모두 나온다.
  static const _htpDetail = {
    'reportId': 502,
    'reportVersion': 1,
    'reportStatus': 'COMPLETED',
    'activityType': 'HTP',
    'childDisplayName': '민준',
    'nonDiagnosticNotice':
        '이 리포트는 아이가 집·나무·사람을 그리고 대화한 과정에서 나타난 특징을 정리한 자료입니다. '
        '아이의 평소 성격이나 심리 상태를 확정하거나 진단하는 결과는 아닙니다.',
    'drawingSession': {
      'drawingSessionId': 121,
      'childId': 3,
      'drawingTypeCode': 'HTP',
      'drawingTypeName': '집-나무-사람',
      'title': '집·나무·사람 이야기',
      'inputMethod': 'CANVAS',
      'startedAt': '2026-07-22T09:40:00',
      'completedAt': '2026-07-22T10:05:00',
      'durationMs': 1500000,
    },
    'drawing': {
      'finalImageUrl': '/api/v1/drawing-assets/121/file',
      'thumbnailUrl': '/api/v1/drawing-assets/121/file',
    },
    'childExpression': {
      'selectedEmotions': ['JOY'],
      'expressedEmotionText': '우리 집이랑 나무 그리는 거 재밌었어요',
      'representativeUtterances': [
        {
          'messageId': 904,
          'text': '이 집에는 우리 가족이 다 같이 살아.',
          'source': 'STT',
          'sttNeedsConfirmation': false,
        },
        {
          'messageId': 905,
          'text': '나무가 나보다 훨씬 커.',
          'source': 'TEXT',
          'sttNeedsConfirmation': false,
        },
      ],
    },
    'observedFeatures': [
      {
        'title': '집을 종이 가운데에 크게 그렸어요',
        'description': '지붕과 창문, 문을 또렷하게 그렸어요.',
        'evidenceSummary': '집 그림에서 확인했어요.',
      },
      {
        'title': '나무에 열매를 여러 개 그렸어요',
        'description': '가지마다 동그란 열매를 촘촘히 그렸어요.',
        'evidenceSummary': '나무 그림에서 확인했어요.',
      },
    ],
    'activityFacts': {
      'detectedObjects': ['집', '나무', '사람'],
      'totalDurationSec': 1500,
      'drawingDurationMs': 1440000,
      'drawingDurationSec': 1440,
      'pauseCount': 6,
      'eraseCount': 3,
      'undoCount': 1,
      'questionCount': 8,
      'answerCount': 6,
      'skipCount': 2,
      'detectedElementCount': 3,
      'pressureAvailable': false,
      'truncated': false,
      'aggregatedHtp': true,
      'notes': ['집·나무·사람 세 활동을 합친 기록'],
    },
    'conversationSummary': {
      'questionCount': 8,
      'answeredCount': 6,
      'skippedCount': 2,
      'summary': '집·나무·사람을 그리며 각 그림에 대해 즐겁게 이야기했어요.',
    },
    'publicInterpretations': [
      {
        'category': 'RELATIONSHIP',
        'title': '가족과의 정서적 연결',
        'tendencyText': '가족과 함께 있는 것을 편안하게 느끼는 모습이 보일 수 있어요.',
        'scopeText': '이번 그림 활동에서 나타난 가능성입니다.',
        'homeObservationGuide': '집 이야기를 할 때 아이의 표정을 함께 살펴봐 주세요.',
        'evidenceRefs': [101],
        'confidence': 'STRONG',
      },
      {
        'category': 'GROWTH',
        'title': '자라고 싶은 마음',
        'tendencyText': '스스로 크고 싶은 마음이 큰 나무 그림에 담겼을 수 있어요.',
        'scopeText': '이번 그림 활동에서 나타난 가능성입니다.',
        'homeObservationGuide': '아이가 "다 컸다"고 말하는 순간을 살펴봐 주세요.',
        'evidenceRefs': [102],
        'confidence': 'MODERATE',
      },
    ],
    'evidenceItems': [
      {
        'evidenceId': 101,
        'sourceType': 'CHILD_ANSWER',
        'text': '집에는 우리 가족이 다 같이 산다고 답했어요.',
      },
      {'evidenceId': 102, 'sourceType': 'VISION', 'text': '나무를 자기 키보다 크게 그렸어요.'},
    ],
    'subjectReports': [
      {
        'subjectType': 'HOUSE',
        'imageUrl': '/api/v1/drawing-assets/121/file',
        'visionObservations': ['지붕과 창문이 있는 집을 가운데에 그렸어요.', '문을 크게 그렸어요.'],
        'qaPairs': [
          {
            'question': '이 집에는 누가 살아요?',
            'answer': '우리 가족이요',
            'state': 'ANSWERED',
            'inputType': 'VOICE',
            'sttNeedsConfirmation': false,
            'isRepresentative': true,
          },
          {
            'question': '집에서 제일 좋아하는 곳은 어디야?',
            'answer': '내 방이요',
            'state': 'ANSWERED',
            'inputType': 'TEXT',
            'sttNeedsConfirmation': false,
            'isRepresentative': false,
          },
        ],
        'interpretationRefs': [0],
      },
      {
        'subjectType': 'TREE',
        'imageUrl': '/api/v1/drawing-assets/121/file',
        'visionObservations': ['큰 나무에 동그란 열매를 여러 개 그렸어요.'],
        'qaPairs': [
          {
            'question': '이 나무는 몇 살이에요?',
            'answer': '아주 많아요',
            'state': 'ANSWERED',
            'inputType': 'VOICE',
            'sttNeedsConfirmation': false,
            'isRepresentative': true,
          },
          {
            'question': '나무에 뭐가 열렸어요?',
            'answer': null,
            'state': 'SKIPPED',
            'inputType': 'TEXT',
            'sttNeedsConfirmation': false,
            'isRepresentative': false,
          },
        ],
        'interpretationRefs': [1],
      },
      {
        'subjectType': 'PERSON',
        'imageUrl': '/api/v1/drawing-assets/121/file',
        'visionObservations': ['웃는 얼굴의 사람을 그렸어요.'],
        'qaPairs': [
          {
            'question': '이 사람은 누구예요?',
            'answer': '나예요',
            'state': 'ANSWERED',
            'inputType': 'VOICE',
            'sttNeedsConfirmation': false,
            'isRepresentative': true,
          },
        ],
        'interpretationRefs': [0],
      },
    ],
    'parentGuides': [
      {
        'guideType': 'DRAWING_CONVERSATION',
        'items': ['집·나무·사람 중에서 제일 그리고 싶었던 그림이 무엇이었는지 물어봐 주세요.'],
      },
      {
        'guideType': 'DAILY_PARENTING',
        'items': ['하루 한 번은 아이의 이야기를 끝까지 들어 주세요.'],
      },
      {
        'guideType': 'HOME_OBSERVATION',
        'items': ['아이가 가족 이야기를 할 때 어떤 표정을 짓는지 살펴봐 주세요.'],
      },
      {
        'guideType': 'PROFESSIONAL_SUPPORT',
        'items': ['더 이야기 나누고 싶을 때는 전문가 상담을 참고할 수 있어요.'],
      },
    ],
    'references': [
      {'title': '아이 그림과 대화 이해하기', 'url': null},
    ],
    'guardianConversationGuide': ['오늘 그린 집에서 제일 좋아하는 곳은 어디야?'],
    'limitations': ['이 리포트는 의료적·심리학적 진단이 아니며, 아이와의 대화를 돕기 위한 관찰 참고 자료입니다.'],
    'expertReview': {'status': 'NOT_REQUESTED', 'available': false},
    'createdAt': '2026-07-22T10:14:00',
  };
  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) async => ApiPage(
    // 그림일기(최신)를 맨 위에, HTP 개발 표본을 아래에 둔다.
    content: [
      ReportSummaryDto.fromJson(_summary),
      ReportSummaryDto.fromJson(_htpSummary),
    ],
    page: 0,
    size: 20,
    totalElements: 2,
    totalPages: 1,
    hasNext: false,
  );
  @override
  Future<ReportDetailDto> getReport(int reportId) async =>
      // 502=HTP 표본, 그 외=그림일기 표본.
      ReportDetailDto.fromJson(reportId == 502 ? _htpDetail : _detail);

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
