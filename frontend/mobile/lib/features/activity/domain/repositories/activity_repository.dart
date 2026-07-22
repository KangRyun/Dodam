import '../../../../core/network/api_page.dart';
import '../../data/dto/activity_dtos.dart';

abstract interface class ActivityRepository {
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  });
  Future<ActivityDetailDto> getActivity(int activityId);
  Future<void> deleteActivity(int activityId);
}
