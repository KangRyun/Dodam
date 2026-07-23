import '../../../../core/network/network.dart';
import '../../domain/repositories/activity_repository.dart';
import '../dto/activity_dtos.dart';

final class RemoteActivityRepository implements ActivityRepository {
  const RemoteActivityRepository(this._apiClient);
  final ApiClient _apiClient;
  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/activities',
      queryParameters: filter.toQueryParameters(),
    );
    return ApiPage.fromJson(response.data!, ActivitySummaryDto.fromJson);
  }

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'activities/$activityId',
    );
    return ActivityDetailDto.fromJson(response.data!);
  }

  @override
  Future<void> deleteActivity(int activityId) async =>
      _apiClient.delete<void>('activities/$activityId');
}
