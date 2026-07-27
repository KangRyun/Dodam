import '../../features/notification/domain/entities/push_message.dart';
import 'app_routes.dart';

/// 푸시 클릭 시 이동할 앱 라우트를 고른다.
///
/// 서버는 이동 URL을 주지 않고 자원 유형·식별자만 준다. 라우트 선택은 앱 몫이며
/// 알림함 클릭(S15P11B209-501)과 같은 규칙을 쓴다
/// (`docs/api/push-notification-delivery-contract.md` §4.3).
///
/// 연결된 자원이 없거나 앱에 대응 화면이 없으면 `null`을 돌려준다. 호출자는
/// 임의 화면으로 보내지 말고 알림함 목록으로 보낸다.
String? resolvePushRoute(PushMessage message) {
  final resourceId = message.resourceId;
  if (resourceId == null) return null;

  return switch (message.resourceType) {
    PushResourceType.report => AppRoutes.report('$resourceId'),
    PushResourceType.drawingSession => AppRoutes.activityDetail('$resourceId'),
    // 커뮤니티는 웹 전용이라 앱에 대응 화면이 없다(CLAUDE.md 6절).
    PushResourceType.post => null,
    null => null,
  };
}
