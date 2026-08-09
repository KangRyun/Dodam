import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTP 활동 기록의 묶음 정보와 세 그림을 파싱한다', () {
    final activity = ActivitySummaryDto.fromJson({
      'drawingSessionId': 12,
      'thumbnailUrl': '/api/v1/drawing-assets/33/file',
      'drawingType': {'code': 'HTP', 'name': '집·나무·사람 그림'},
      'title': null,
      'inputMethod': 'CANVAS',
      'sessionStatus': 'COMPLETED',
      'selectedEmotions': ['CALM'],
      'analysisStatus': 'SUCCEEDED',
      'reportId': 50,
      'reportStatus': 'COMPLETED',
      'startedAt': '2026-07-20T09:40:00Z',
      'completedAt': '2026-07-20T10:03:00Z',
      'activityKind': 'HTP',
      'htpAssessmentId': 40,
      'htpStatus': 'COMPLETED',
      'htpDrawings': [
        {
          'drawingSubject': 'HOUSE',
          'drawingSessionId': 10,
          'thumbnailUrl': '/api/v1/drawing-assets/31/file',
        },
        {
          'drawingSubject': 'TREE',
          'drawingSessionId': 11,
          'thumbnailUrl': '/api/v1/drawing-assets/32/file',
        },
        {
          'drawingSubject': 'PERSON',
          'drawingSessionId': 12,
          'thumbnailUrl': '/api/v1/drawing-assets/33/file',
        },
      ],
    });

    expect(activity.isHtp, isTrue);
    expect(activity.htpAssessmentId, 40);
    expect(activity.htpDrawings.map((drawing) => drawing.drawingSubject), [
      'HOUSE',
      'TREE',
      'PERSON',
    ]);
    expect(activity.report?.reportId, 50);
  });
}
