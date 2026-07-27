import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/router/push_route_resolver.dart';
import 'package:dodam/features/notification/domain/entities/push_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PushMessage message({PushResourceType? resourceType, int? resourceId}) =>
      PushMessage(
        notificationId: 900,
        type: 'ANALYSIS_COMPLETED',
        title: '분석이 완료됐어요',
        content: '리포트를 확인해 보세요',
        resourceType: resourceType,
        resourceId: resourceId,
      );

  test('리포트 알림은 리포트 상세로 보낸다', () {
    final route = resolvePushRoute(
      message(resourceType: PushResourceType.report, resourceId: 55),
    );

    expect(route, AppRoutes.report('55'));
  });

  test('활동 알림은 활동 상세로 보낸다', () {
    final route = resolvePushRoute(
      message(resourceType: PushResourceType.drawingSession, resourceId: 7),
    );

    expect(route, AppRoutes.activityDetail('7'));
  });

  test('연결 자원이 없으면 라우트를 정하지 않는다', () {
    // 호출자가 알림함 목록으로 보내야 한다. 임의 화면으로 보내지 않는다.
    expect(resolvePushRoute(message()), isNull);
  });

  test('커뮤니티 게시글은 앱에 대응 화면이 없어 라우트를 정하지 않는다', () {
    final route = resolvePushRoute(
      message(resourceType: PushResourceType.post, resourceId: 12),
    );

    expect(route, isNull);
  });
}
