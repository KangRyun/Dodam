import '../../features/notification/domain/entities/push_message.dart';
import 'app_routes.dart';

/// 알림이 가리키는 상세 화면 라우트를 고른다.
///
/// 서버는 이동 URL·딥링크를 만들지 않고 자원 유형·식별자만 준다. 라우트 선택은
/// 앱 몫이며, **푸시 클릭과 알림함 카드 클릭이 이 함수 하나를 함께 쓴다**
/// (`docs/api/push-notification-delivery-contract.md` §4.3, S15P11B209-501).
///
/// 유형·식별자 중 하나라도 없으면 `null`을 돌려준다. 계약이 정한 3종 밖의
/// 값도 파싱 단계에서 `null`이 되어 같은 취급을 받는다. 호출자는 임의 화면으로
/// 보내지 말고 알림함 목록을 기본값으로 삼는다.
String? resolveNotificationRoute({
  required PushResourceType? resourceType,
  required int? resourceId,
}) {
  if (resourceType == null || resourceId == null) return null;

  return switch (resourceType) {
    PushResourceType.report => AppRoutes.report('$resourceId'),
    PushResourceType.drawingSession => AppRoutes.activityDetail('$resourceId'),
    // 앱에는 네이티브 게시글 화면이 없다. 계약이 요구하는 `POST` 매핑
    // (`docs/api/push-notification-delivery-contract.md` §4.3 표)은 이미 있는
    // 커뮤니티 웹뷰를 게시글 주소로 열어 만족시킨다. 대응 웹 라우트는
    // `frontend/web/src/app/community/posts/[postId]`다.
    PushResourceType.post => AppRoutes.communityPost('$resourceId'),
  };
}

/// 알림함 항목이 가리키는 상세 화면 라우트를 고른다.
///
/// 알림함 응답은 자원 유형을 계약 어휘 문자열로 주므로 여기서 한 번 파싱해
/// [resolveNotificationRoute]에 넘긴다. 계약에 없는 문자열은 `null`이 된다.
String? resolveNotificationItemRoute({
  required String? relatedResourceType,
  required int? relatedResourceId,
}) => resolveNotificationRoute(
  resourceType: PushResourceType.tryParse(relatedResourceType),
  resourceId: relatedResourceId,
);

/// 푸시 클릭 시 열 라우트를 고른다.
///
/// 연결 자원이 없으면 알림함 목록으로 보낸다(계약 §4.3). 항상 라우트를 돌려주므로
/// 호출부가 기본값 처리를 잊어 아무 데도 가지 않는 일이 생기지 않는다.
String resolvePushRoute(PushMessage message) =>
    resolveNotificationRoute(
      resourceType: message.resourceType,
      resourceId: message.resourceId,
    ) ??
    AppRoutes.notifications;
