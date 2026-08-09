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

  /// 활동에 연결된 대화(CONV-02)의 질문·답변 메시지를 모두 가져온다.
  ///
  /// [conversationId]는 [ActivityDetailDto.conversationId]에서 얻는다. 대화가
  /// 없는 활동은 그 값이 null이므로 호출자가 먼저 걸러야 한다.
  ///
  /// 응답이 여러 페이지로 나뉘어도 구현이 이어서 모두 읽고, 중복
  /// `messageId`를 걸러 `sequence` 오름차순으로 돌려준다.
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  );

  /// [ActivitySummaryDto.thumbnailUrl] / [ActivityAssetDto.fileUrl]가
  /// 가리키는 그림 이미지를 인증된 요청으로 내려받는다.
  Future<Uint8List> downloadImage(String url);
}
