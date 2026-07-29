import 'dart:typed_data';

import '../../../../core/network/api_page.dart';
import '../../data/dto/activity_dtos.dart';

abstract interface class ActivityRepository {
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  });
  Future<ActivityDetailDto> getActivity(int activityId);
  Future<void> deleteActivity(int activityId);

  /// [ActivitySummaryDto.thumbnailUrl] / [ActivityAssetDto.fileUrl]가
  /// 가리키는 그림 이미지를 인증된 요청으로 내려받는다.
  Future<Uint8List> downloadImage(String url);
}
