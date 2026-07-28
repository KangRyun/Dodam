import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/data/repositories/mock_activity_repository.dart';
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
      final session = DrawingSessionDto.fromJson(const {
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
    test('parses activity detail summaries', () {
      final detail = ActivityDetailDto.fromJson({
        ...summaryJson,
        'childId': 3,
        'currentStage': 'DRAFT',
        'expressedEmotionText': null,
        'assets': [],
        'conversation': null,
        'analysis': null,
      });
      expect(detail.activityId, 120);
      expect(detail.assets, isEmpty);
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
