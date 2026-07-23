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
    'thumbnailUrl': 'https://storage.i15b209.example/previews/ds120-v1.png',
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
  @override
  Future<ActivityDetailDto> getActivity(int activityId) async =>
      ActivityDetailDto.fromJson({
        ..._summary,
        'childId': 3,
        'currentStage': 'COMPLETED',
        'expressedEmotionText': '동생이랑 놀아서 좋았어',
        'assets': [
          {
            'assetId': 900,
            'assetType': 'FINAL',
            'assetVersion': 2,
            'fileUrl': 'https://storage.i15b209.example/final/ds120-v2.png',
            'mimeType': 'image/png',
            'widthPx': 1600,
            'heightPx': 1000,
          },
        ],
        'conversation': {
          'conversationSessionId': 77,
          'conversationStatus': 'COMPLETED',
          'questionCount': 6,
          'completedAt': '2026-07-20T10:01:00Z',
        },
        'analysis': {
          'analysisId': 88,
          'analysisStatus': 'COMPLETED',
          'completedAt': '2026-07-20T10:11:00Z',
        },
        'report': {
          'reportId': 501,
          'reportStatus': 'COMPLETED',
          'reportVersion': 1,
        },
      });
  @override
  Future<void> deleteActivity(int activityId) async {}
}
