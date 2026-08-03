import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/network/api_page.dart';
import '../../domain/repositories/activity_repository.dart';
import '../dto/activity_dtos.dart';

final class MockActivityRepository implements ActivityRepository {
  const MockActivityRepository();
  static const _summary = {
    'activityId': 120,
    'title': '우리 가족',
    'drawingType': {'code': 'ART_DIARY', 'name': '그림일기'},
    'inputMethod': 'CANVAS',
    'sessionStatus': 'COMPLETED',
    'selectedEmotions': ['JOY', 'UNSURE'],
    'thumbnailUrl': '/api/v1/drawing-assets/120/file',
    'analysisStatus': 'COMPLETED',
    'report': {'reportId': 501, 'reportStatus': 'COMPLETED'},
    'startedAt': '2026-07-20T09:40:00Z',
    'completedAt': '2026-07-20T10:03:00Z',
  };
  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async => ApiPage(
    content: [ActivitySummaryDto.fromJson(_summary)],
    page: 0,
    size: 20,
    totalElements: 1,
    totalPages: 1,
    hasNext: false,
  );

  /// 백엔드 `DrawingSessionDetailResponse`와 같은 모양이다.
  @override
  Future<ActivityDetailDto> getActivity(int activityId) async =>
      ActivityDetailDto.fromJson({
        'drawingSessionId': 120,
        'child': {'childId': 3, 'nickname': '도담이'},
        'drawingType': {
          'drawingTypeId': 5,
          'code': 'ART_DIARY',
          'name': '그림일기',
        },
        'inputMethod': 'CANVAS',
        'title': '우리 가족',
        'selectedEmotions': ['JOY', 'UNSURE'],
        'sessionStatus': 'COMPLETED',
        'currentStage': 'COMPLETED',
        'latestAsset': {
          'drawingAssetId': 900,
          'assetType': 'FINAL',
          'assetVersion': 2,
          'mimeType': 'image/png',
          'fileSizeBytes': 240110,
          'widthPx': 1600,
          'heightPx': 1000,
          'capturedAt': '2026-07-20T10:02:00Z',
          'createdAt': '2026-07-20T10:02:01Z',
        },
        'latestAnalysis': {
          'drawingAnalysisId': 88,
          'analysisScope': 'FINAL',
          'analysisType': 'DRAWING_INTERPRETATION',
          'analysisStatus': 'COMPLETED',
          'requestedAt': '2026-07-20T10:05:00Z',
          'completedAt': '2026-07-20T10:11:00Z',
        },
        'conversationId': 77,
        'reportId': 501,
        'startedAt': '2026-07-20T09:40:00Z',
        'completedAt': '2026-07-20T10:03:00Z',
        'recoverableDraft': false,
      });

  /// 보호자 상세 화면이 다루어야 하는 답변 형태를 한 대화에 모아 둔다 —
  /// 선택형·직접 입력·음성 STT 성공·변환 중·변환 실패·건너뛴 질문·무답변.
  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) async => [
    for (final message in _messages)
      ActivityConversationMessageDto.fromJson(message),
  ];

  static const _messages = <Map<String, dynamic>>[
    {
      'messageId': 801,
      'parentMessageId': null,
      'sequence': 1,
      'senderType': 'AI',
      'messageType': 'QUESTION',
      'rawText': '이 그림에서 가장 마음에 드는 곳은 어디야?',
      'options': [
        {
          'optionId': 'HOUSE',
          'type': 'OPTION',
          'label': '집',
          'value': 'HOUSE',
          'emoji': '🏠',
        },
        {
          'optionId': 'PERSON',
          'type': 'OPTION',
          'label': '사람',
          'value': 'PERSON',
          'emoji': '🙂',
        },
      ],
      'targetObject': {'objectCode': 'HOUSE', 'objectName': '집'},
      'isSkipped': false,
      'createdAt': '2026-07-20T09:52:00',
    },
    {
      'messageId': 802,
      'parentMessageId': 801,
      'sequence': 2,
      'senderType': 'CHILD',
      'messageType': 'ANSWER_OPTION',
      'selectedResponse': {
        'selectedOptions': [
          {
            'optionId': 'HOUSE',
            'type': 'STATIC',
            'value': 'HOUSE',
            'labelSnapshot': '집',
          },
        ],
        'directText': '우리 집 지붕이 제일 좋아',
      },
      'isSkipped': false,
      'createdAt': '2026-07-20T09:52:20',
    },
    {
      'messageId': 803,
      'parentMessageId': null,
      'sequence': 3,
      'senderType': 'AI',
      'messageType': 'QUESTION',
      'rawText': '집 앞에 있는 사람은 누구야?',
      'options': <Map<String, dynamic>>[],
      'isSkipped': false,
      'createdAt': '2026-07-20T09:53:00',
    },
    {
      'messageId': 804,
      'parentMessageId': 803,
      'sequence': 4,
      'senderType': 'CHILD',
      'messageType': 'ANSWER_VOICE',
      'sttText': '엄마랑 동생이야',
      'speechStatus': 'SUCCESS',
      'sttConfidence': 0.91,
      'isSkipped': false,
      'createdAt': '2026-07-20T09:53:30',
    },
    {
      'messageId': 805,
      'parentMessageId': null,
      'sequence': 5,
      'senderType': 'AI',
      'messageType': 'QUESTION',
      'rawText': '그때 기분은 어땠어?',
      'options': <Map<String, dynamic>>[],
      'isSkipped': false,
      'createdAt': '2026-07-20T09:54:00',
    },
    {
      'messageId': 806,
      'parentMessageId': 805,
      'sequence': 6,
      'senderType': 'CHILD',
      'messageType': 'ANSWER_VOICE',
      'sttText': null,
      'speechStatus': 'PROCESSING',
      'isSkipped': false,
      'createdAt': '2026-07-20T09:54:20',
    },
    {
      'messageId': 807,
      'parentMessageId': null,
      'sequence': 7,
      'senderType': 'AI',
      'messageType': 'QUESTION',
      'rawText': '또 그리고 싶은 게 있어?',
      'options': <Map<String, dynamic>>[],
      'isSkipped': true,
      'createdAt': '2026-07-20T09:55:00',
    },
    {
      'messageId': 808,
      'parentMessageId': null,
      'sequence': 8,
      'senderType': 'AI',
      'messageType': 'QUESTION',
      'rawText': '오늘 그림을 누구에게 보여주고 싶어?',
      'options': <Map<String, dynamic>>[],
      'isSkipped': false,
      'createdAt': '2026-07-20T09:56:00',
    },
    {
      'messageId': 809,
      'parentMessageId': 808,
      'sequence': 9,
      'senderType': 'CHILD',
      'messageType': 'ANSWER_VOICE',
      'sttText': null,
      'speechStatus': 'FAILED',
      'isSkipped': false,
      'createdAt': '2026-07-20T09:56:30',
    },
  ];

  @override
  Future<void> deleteActivity(int activityId) async {}

  @override
  Future<Uint8List> downloadImage(String url) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1Pe'
    'AAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );
}
