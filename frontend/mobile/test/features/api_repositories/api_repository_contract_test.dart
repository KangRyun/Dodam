import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/data/repositories/mock_activity_repository.dart';
import 'package:dodam/features/activity/domain/models/activity_conversation_turn.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/data/repositories/mock_child_repository.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/data/repositories/mock_drawing_repository.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/data/repositories/mock_report_repository.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Child contract', () {
    const childJson = {
      'childId': 3,
      'nickname': '도담이',
      'birthDate': '2019-03-14',
      'age': 7,
      'profileImageUrl': null,
      'preferredCharacter': 'BEAR',
      'questionDifficulty': 'PRESCHOOL',
      'responseModes': ['VOICE', 'OPTION'],
      'tutorialStatus': 'COMPLETED',
      'profileStatus': 'ACTIVE',
      'relationshipType': 'MOTHER',
      'createdAt': '2026-07-01T02:10:00Z',
      'updatedAt': '2026-07-18T11:42:00Z',
    };

    test('parses list and detail nullable fields', () {
      final summary = ChildSummaryDto.fromJson({
        ...childJson,
        'recentActivity': {'lastActivityAt': null, 'totalActivityCount': 0},
      });
      final detail = ChildDetailDto.fromJson(childJson);
      expect(summary.profileImageUrl, isNull);
      expect(summary.recentActivity.lastActivityAt, isNull);
      expect(detail.responseModes, ['VOICE', 'OPTION']);
    });

    test('serializes create and PATCH explicit image null', () {
      final create = CreateChildRequestDto(
        nickname: '도담이',
        birthDate: '2019-03-14',
        relationshipType: 'MOTHER',
        questionDifficulty: 'LOWER_ELEMENTARY',
        responseModes: const ['VOICE'],
      );
      const update = UpdateChildRequestDto(
        questionDifficulty: 'ELEMENTARY',
        includeProfileImageUrl: true,
      );
      expect(create.toJson(), {
        'nickname': '도담이',
        'birthDate': '2019-03-14',
        'relationshipType': 'MOTHER',
        'questionDifficulty': 'LOWER_ELEMENTARY',
        'responseModes': ['VOICE'],
      });
      expect(update.toJson(), containsPair('profileImageUrl', null));
    });
  });

  group('Drawing contract', () {
    test('parses a DrawingSession response', () {
      final session = DrawingSessionDto.fromCreateJson(const {
        'drawingSessionId': 42,
        'childId': 3,
        'drawingType': {
          'drawingTypeId': 5,
          'code': 'ART_DIARY',
          'name': '그림일기',
        },
        'inputMethod': 'CANVAS',
        'title': null,
        'sessionStatus': 'DRAWING',
        'currentStage': 'DRAWING',
        'selectedEmotions': null,
        'expressedEmotionText': null,
        'startedAt': '2026-07-21T09:30:00Z',
        'completedAt': null,
        'conversation': null,
        'latestAnalysis': null,
        'assets': [],
      });
      expect(session.drawingType.code, 'ART_DIARY');
      expect(session.completedAt, isNull);
    });

    test('serializes stroke batches and omits unsupported pressure', () {
      const request = StrokeBatchRequestDto(
        batchSequence: 12,
        firstEventSequence: 1103,
        lastEventSequence: 1105,
        clientCreatedAt: '2026-07-21T09:41:03.120Z',
        events: [
          StrokeBatchEventDto(
            sequence: 1103,
            eventType: 'STROKE',
            tool: 'PEN',
            color: '#E8823C',
            width: 8,
            points: [
              StrokePointDto(x: 0.42, y: 0.61, t: 0),
              StrokePointDto(x: 0.5, y: 0.7, t: 16),
            ],
          ),
          StrokeBatchEventDto(sequence: 1105, eventType: 'UNDO', points: []),
        ],
        metrics: StrokeMetricsDto(undoCountDelta: 1),
      );
      final json = request.toJson();
      expect(json, isNot(contains('eventCount')));
      expect(
        ((json['events'] as List).first as Map)['points'],
        everyElement(isNot(contains('pressure'))),
      );
      expect(json['metrics'], containsPair('undoCountDelta', 1));
    });

    test('parses draft recovery and object detection responses', () {
      final draft = DraftRecoveryDto.fromJson(const {
        'previewUrl': 'https://example.com/draft.png',
        'canvasState': {
          'lastEventSequence': 1105,
          'toolState': null,
          'viewport': null,
          'clientSavedAt': '2026-07-21T09:41:10Z',
        },
        'assetVersion': 3,
      });
      final detection = ObjectDetectionResponseDto.fromJson(const {
        'drawingAnalysisId': 15901,
        'drawingSessionId': 481,
        'drawingAssetId': 120,
        'requestId': '550e8400-e29b-41d4-a716-446655440000',
        'analysisType': 'OBJECT_DETECTION',
        'status': 'SUCCEEDED',
        'model': {'name': 'dodam-detector', 'version': '1.0'},
        'detections': [
          {
            'label': 'HOUSE',
            'confidence': 0.94,
            'boundingBox': {'x': 10, 'y': 20, 'width': 30, 'height': 40},
          },
        ],
        'requestedAt': '2026-07-21T09:41:12Z',
        'processedAt': '2026-07-21T09:41:13Z',
      });
      expect(draft.previewUrl, 'https://example.com/draft.png');
      expect(draft.canvasState.lastEventSequence, 1105);
      expect(draft.assetVersion, 3);
      expect(detection.drawingAssetId, 120);
      expect(detection.detections.single.label, 'HOUSE');
    });
  });

  group('Activity contract', () {
    const summaryJson = {
      'activityId': 120,
      'title': null,
      'drawingType': {'code': 'FREE_DRAWING', 'name': '자유화'},
      'inputMethod': 'CANVAS',
      'sessionStatus': 'DRAFT',
      'selectedEmotions': [],
      'thumbnailUrl': null,
      'analysisStatus': null,
      'report': null,
      'startedAt': '2026-07-21T08:10:00Z',
      'completedAt': null,
    };
    test('parses ApiPage<ActivitySummaryDto>', () {
      final page = ApiPage.fromJson({
        'content': [summaryJson],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
        'hasNext': false,
      }, ActivitySummaryDto.fromJson);
      expect(page.content.single.report, isNull);
    });
    test('parses backend DrawingSessionDetailResponse shape', () {
      // 실백엔드 상세는 drawingSessionId·child{}·latestAsset·latestAnalysis와
      // 최상위 conversationId·reportId를 준다. 구형 계약(activityId·assets[]·
      // 중첩 conversation{})은 실제로 오지 않는다.
      final detail = ActivityDetailDto.fromJson(const {
        'drawingSessionId': 120,
        'child': {'childId': 3, 'nickname': '도담이'},
        'drawingType': {
          'drawingTypeId': 5,
          'code': 'HTP_HOUSE',
          'name': 'HTP 집',
        },
        'inputMethod': 'CANVAS',
        'title': '우리 집',
        'selectedEmotions': ['HAPPY'],
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
          'capturedAt': '2026-07-21T08:21:00Z',
          'createdAt': '2026-07-21T08:21:01Z',
        },
        'latestAnalysis': {
          'drawingAnalysisId': 88,
          'analysisScope': 'FINAL',
          'analysisType': 'DRAWING_INTERPRETATION',
          'analysisStatus': 'COMPLETED',
          'requestedAt': '2026-07-21T08:23:00Z',
          'completedAt': '2026-07-21T08:24:00Z',
        },
        'conversationId': 77,
        'reportId': 501,
        'startedAt': '2026-07-21T08:10:00Z',
        'completedAt': '2026-07-21T08:22:00Z',
        'recoverableDraft': false,
      });

      expect(detail.activityId, 120);
      expect(detail.childId, 3);
      expect(detail.childNickname, '도담이');
      expect(detail.conversationId, 77);
      expect(detail.reportId, 501);
      expect(detail.latestAnalysis?.drawingAnalysisId, 88);
      expect(detail.latestAnalysis?.analysisStatus, 'COMPLETED');
      // 응답에 파일 URL이 없으므로 식별자로 인증 조회 경로를 만든다.
      expect(detail.latestAsset?.fileUrl, '/api/v1/drawing-assets/900/file');
      expect(detail.recoverableDraft, isFalse);
    });

    test('parses a detail with no conversation and no linked resources', () {
      final detail = ActivityDetailDto.fromJson(const {
        'drawingSessionId': 121,
        'child': {'childId': 3, 'nickname': null},
        'drawingType': {
          'drawingTypeId': 5,
          'code': 'FREE_DRAWING',
          'name': '자유화',
        },
        'inputMethod': 'CANVAS',
        'title': null,
        'selectedEmotions': <String>[],
        'sessionStatus': 'DRAFT',
        'currentStage': 'DRAWING',
        'latestAsset': null,
        'latestAnalysis': null,
        'conversationId': null,
        'reportId': null,
        'startedAt': '2026-07-21T08:10:00Z',
        'completedAt': null,
        'recoverableDraft': true,
      });

      expect(detail.conversationId, isNull);
      expect(detail.reportId, isNull);
      expect(detail.latestAsset, isNull);
      expect(detail.latestAnalysis, isNull);
      expect(detail.childNickname, isNull);
      expect(detail.selectedEmotions, isEmpty);
      expect(detail.completedAt, isNull);
      expect(detail.recoverableDraft, isTrue);
    });
    test('parses backend HISTORY-01 shape (drawingSessionId, 평면 report)', () {
      // 실백엔드 활동 기록 목록은 drawingSessionId와 평면 reportId/reportStatus를
      // 준다(중첩 report{} 아님). 매핑이 이 형태를 올바로 읽어야 한다.
      final page = ApiPage.fromJson({
        'content': [
          {
            'drawingSessionId': 120,
            'title': '우리 집 그리기',
            'drawingType': {'code': 'HTP_HOUSE', 'name': 'HTP 집'},
            'inputMethod': 'CANVAS',
            'sessionStatus': 'COMPLETED',
            'currentStage': 'COMPLETED',
            'selectedEmotions': ['HAPPY'],
            'analysisStatus': 'COMPLETED',
            'reportId': 501,
            'reportStatus': 'COMPLETED',
            'startedAt': '2026-07-21T08:10:00Z',
            'completedAt': '2026-07-21T08:22:00Z',
          },
        ],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
        'hasNext': false,
      }, ActivitySummaryDto.fromJson);
      final item = page.content.single;
      expect(item.activityId, 120);
      expect(item.report?.reportId, 501);
      expect(item.report?.reportStatus, 'COMPLETED');
    });
  });

  group('Conversation message contract (CONV-02)', () {
    test('parses a question with options and target object', () {
      final question = ActivityConversationMessageDto.fromJson(const {
        'messageId': 803,
        'parentMessageId': null,
        'sequence': 3,
        'senderType': 'AI',
        'messageType': 'QUESTION',
        'rawText': '이 사람 기분은?',
        'sttText': null,
        'speechStatus': null,
        'sttConfidence': null,
        'needsGuardianConfirmation': false,
        'isSkipped': false,
        'options': [
          {
            'optionId': 'happy',
            'type': 'EMOTION',
            'label': '기뻐요',
            'value': 'HAPPY',
            'emoji': '🙂',
          },
        ],
        'selectedResponse': null,
        'targetObject': {
          'objectCode': 'PERSON',
          'objectName': '사람',
          'boundingBox': {'x': 0.15, 'y': 0.2, 'width': 0.25, 'height': 0.5},
        },
        'createdAt': '2026-07-21T02:36:00',
      });

      expect(question.isQuestion, isTrue);
      expect(question.parentMessageId, isNull);
      expect(question.options.single.label, '기뻐요');
      expect(question.options.single.emoji, '🙂');
      expect(question.targetObject?.objectName, '사람');
      expect(question.selectedResponse, isNull);
      expect(question.sttConfidence, isNull);
    });

    test('parses a voice answer with STT fields', () {
      final voice = ActivityConversationMessageDto.fromJson(const {
        'messageId': 804,
        'parentMessageId': 803,
        'sequence': 4,
        'senderType': 'CHILD',
        'messageType': 'ANSWER_VOICE',
        'rawText': null,
        'sttText': '친구랑 같이 있어서 좋아',
        'speechStatus': 'SUCCESS',
        'sttConfidence': 0.91,
        'needsGuardianConfirmation': false,
        'isSkipped': false,
        'options': <Map<String, dynamic>>[],
        'selectedResponse': null,
        'targetObject': null,
        'createdAt': '2026-07-21T02:36:12',
      });

      expect(voice.isQuestion, isFalse);
      expect(voice.parentMessageId, 803);
      expect(voice.sttText, '친구랑 같이 있어서 좋아');
      expect(voice.speechStatus, 'SUCCESS');
      expect(voice.sttConfidence, closeTo(0.91, 1e-9));
      expect(voice.options, isEmpty);
      expect(voice.targetObject, isNull);
    });

    test('parses an option answer with direct text', () {
      final answer = ActivityConversationMessageDto.fromJson(const {
        'messageId': 806,
        'parentMessageId': 805,
        'sequence': 6,
        'senderType': 'CHILD',
        'messageType': 'ANSWER_OPTION',
        'isSkipped': false,
        'options': <Map<String, dynamic>>[],
        'selectedResponse': {
          'selectedOptions': [
            {
              'optionId': 'HOUSE',
              'type': 'STATIC',
              'value': 'HOUSE',
              'labelSnapshot': '집',
            },
          ],
          'directText': '우리 집 지붕',
        },
        'createdAt': '2026-07-21T02:37:00',
      });

      expect(
        answer.selectedResponse?.selectedOptions.single.labelSnapshot,
        '집',
      );
      expect(answer.selectedResponse?.directText, '우리 집 지붕');
      // 유형별로 채워지지 않는 필드는 없어도 파싱이 깨지지 않는다.
      expect(answer.rawText, isNull);
      expect(answer.speechStatus, isNull);
      expect(answer.needsGuardianConfirmation, isFalse);
    });

    test('parses ApiPage envelope metadata for a message page', () {
      final page = ApiPage.fromJson({
        'content': [
          {
            'messageId': 801,
            'sequence': 1,
            'senderType': 'AI',
            'messageType': 'QUESTION',
            'rawText': '무엇을 그렸어?',
          },
        ],
        'page': 0,
        'size': 50,
        'totalElements': 12,
        'totalPages': 1,
        'first': true,
        'last': true,
        'hasNext': false,
      }, ActivityConversationMessageDto.fromJson);

      expect(page.content.single.messageId, 801);
      expect(page.totalElements, 12);
      expect(page.hasNext, isFalse);
    });

    test('groups answers under questions by parentMessageId', () {
      final turns = ActivityConversationTurn.group(const [
        ActivityConversationMessageDto(
          messageId: 804,
          sequence: 4,
          senderType: 'CHILD',
          messageType: 'ANSWER_VOICE',
          parentMessageId: 803,
          sttText: '엄마야',
          speechStatus: 'SUCCESS',
        ),
        ActivityConversationMessageDto(
          messageId: 803,
          sequence: 3,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '이 사람은 누구야?',
        ),
        ActivityConversationMessageDto(
          messageId: 805,
          sequence: 5,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '건너뛴 질문',
          isSkipped: true,
        ),
      ]);

      expect(turns, hasLength(2));
      expect(turns.first.question?.messageId, 803);
      expect(turns.first.answers.single.messageId, 804);
      expect(turns.last.question?.messageId, 805);
      expect(turns.last.hasNoAnswer, isTrue);
    });

    test('keeps valid orphan child answers and excludes other messages', () {
      final turns = ActivityConversationTurn.group(const [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'CHILD',
          messageType: 'ANSWER_TEXT',
          // 질문이 이 목록에 없다(다른 페이지 경계 등).
          parentMessageId: 900,
          rawText: '고아 답변',
        ),
        ActivityConversationMessageDto(
          messageId: 902,
          sequence: 2,
          senderType: 'SYSTEM',
          messageType: 'SYSTEM',
          rawText: '시스템 알림',
        ),
        ActivityConversationMessageDto(
          messageId: 903,
          sequence: 3,
          senderType: 'AI',
          messageType: 'ANSWER_TEXT',
          rawText: '비아동 답변',
        ),
        ActivityConversationMessageDto(
          messageId: 904,
          sequence: 4,
          senderType: 'CHILD',
          messageType: 'FUTURE_UNKNOWN_TYPE',
          rawText: '알 수 없는 유형',
        ),
      ]);

      expect(turns, hasLength(1));
      expect(turns.single.question, isNull);
      expect(turns.first.answers.single.messageId, 901);
    });

    test('drops duplicate messageIds and sorts by sequence', () {
      final ordered = ActivityConversationTurn.order(const [
        ActivityConversationMessageDto(
          messageId: 803,
          sequence: 3,
          senderType: 'AI',
          messageType: 'QUESTION',
        ),
        ActivityConversationMessageDto(
          messageId: 801,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
        ),
        ActivityConversationMessageDto(
          messageId: 803,
          sequence: 3,
          senderType: 'AI',
          messageType: 'QUESTION',
        ),
      ]);

      expect(ordered.map((message) => message.messageId).toList(), [801, 803]);
    });
  });

  group('Report and analysis contract', () {
    test('parses completed report sections', () {
      final report = ReportDetailDto.fromJson(
        _reportJson('COMPLETED', includeSections: true),
      );
      expect(report.drawingSession!.drawingTypeName, '그림일기');
      expect(
        report.childExpression!.representativeUtterances.single.messageId,
        804,
      );
      expect(report.limitations, isNotEmpty);
    });
    test('allows GENERATING and FAILED detail sections to be null', () {
      for (final status in ['GENERATING', 'FAILED']) {
        final report = ReportDetailDto.fromJson(_reportJson(status));
        expect(report.drawingSession, isNull);
        expect(report.childExpression, isNull);
        expect(report.limitations, isEmpty);
        expect(report.hasNoObservations, isTrue);
      }
    });
    test('parses PENDING RUNNING COMPLETED and FAILED analysis states', () {
      for (final status in ['PENDING', 'RUNNING', 'COMPLETED', 'FAILED']) {
        final dto = AnalysisStatusDto.fromJson({
          'analysisId': 15901,
          'analysisType': 'FINAL',
          'analysisStatus': status,
          if (status == 'FAILED') 'errorCode': 'ANALYSIS_MODEL_TIMEOUT',
          if (status == 'FAILED') 'message': '분석에 실패했어요. 다시 시도할 수 있어요.',
        });
        expect(dto.analysisStatus, status);
      }
    });
  });

  test('Mock repositories satisfy their public interfaces', () async {
    const ChildRepository child = MockChildRepository();
    const DrawingRepository drawing = MockDrawingRepository();
    const ActivityRepository activity = MockActivityRepository();
    const ReportRepository report = MockReportRepository();
    expect(await child.getChildren(), isNotEmpty);
    expect((await drawing.getDrawingTypes(childId: 3)).content, isNotEmpty);
    expect((await activity.getActivities(3)).content, isNotEmpty);
    expect((await report.getReports(3)).content, isNotEmpty);

    final detail = await activity.getActivity(120);
    expect(detail.conversationId, isNotNull);
    final messages = await activity.getConversationMessages(
      detail.conversationId!,
    );
    expect(messages, isNotEmpty);
    expect(messages.first.isQuestion, isTrue);
  });
}

/// REPORT-02 보호자 공개 계약(§13.4)의 `data` 페이로드.
/// GENERATING·FAILED는 같은 모양으로 오되 섹션이 비어 있다.
Map<String, dynamic> _reportJson(
  String status, {
  bool includeSections = false,
}) => {
  'reportId': 501,
  'reportVersion': 1,
  'reportStatus': status,
  'drawingSession': includeSections
      ? {
          'drawingSessionId': 120,
          'childId': 3,
          'drawingTypeCode': 'ART_DIARY',
          'drawingTypeName': '그림일기',
          'title': '우리 가족',
          'inputMethod': 'CANVAS',
          'startedAt': '2026-07-20T09:40:00',
          'completedAt': '2026-07-20T10:03:00',
          'durationMs': 1380000,
        }
      : null,
  'drawing': includeSections
      ? {'finalImageUrl': 'https://example.com/final.png', 'thumbnailUrl': null}
      : null,
  'childExpression': includeSections
      ? {
          'selectedEmotions': ['JOY'],
          'expressedEmotionText': '동생이랑 놀아서 좋았어요',
          'representativeUtterances': [
            {
              'messageId': 804,
              'text': '우리 동생이야.',
              'source': 'STT',
              'sttNeedsConfirmation': false,
            },
          ],
        }
      : null,
  'activityFacts': includeSections
      ? {
          'detectedObjects': ['사람'],
          'drawingDurationMs': 1320000,
          'pauseCount': 4,
          'eraseCount': 2,
          'pressureAvailable': false,
          'notes': <String>[],
        }
      : null,
  'conversationSummary': includeSections
      ? {
          'questionCount': 5,
          'answeredCount': 4,
          'skippedCount': 1,
          'summary': '편안하게 대화했어요.',
        }
      : null,
  'guardianConversationGuide': includeSections ? ['어떤 부분이 좋아?'] : <String>[],
  'limitations': includeSections ? ['이 리포트는 진단이 아닌 관찰 참고 자료입니다.'] : <String>[],
  'expertReview': includeSections
      ? {'status': 'NOT_REQUESTED', 'available': false}
      : null,
  'createdAt': '2026-07-20T10:12:00',
};
