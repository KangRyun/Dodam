import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/router/notification_route_resolver.dart';
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

  group('resolveNotificationRoute', () {
    test('리포트 알림은 리포트 상세로 보낸다', () {
      expect(
        resolveNotificationRoute(
          resourceType: PushResourceType.report,
          resourceId: 55,
        ),
        AppRoutes.report('55'),
      );
    });

    test('활동 알림은 활동 상세로 보낸다', () {
      expect(
        resolveNotificationRoute(
          resourceType: PushResourceType.drawingSession,
          resourceId: 7,
        ),
        AppRoutes.activityDetail('7'),
      );
    });

    test('게시글 알림은 커뮤니티 게시글 상세로 보낸다', () {
      expect(
        resolveNotificationRoute(
          resourceType: PushResourceType.post,
          resourceId: 12,
        ),
        AppRoutes.communityPost('12'),
      );
    });

    test('유형만 있고 식별자가 없으면 라우트를 정하지 않는다', () {
      expect(
        resolveNotificationRoute(
          resourceType: PushResourceType.report,
          resourceId: null,
        ),
        isNull,
      );
    });

    test('두 값이 모두 없으면 라우트를 정하지 않는다', () {
      expect(
        resolveNotificationRoute(resourceType: null, resourceId: null),
        isNull,
      );
    });
  });

  group('resolveNotificationItemRoute', () {
    test('알림함 항목의 계약 어휘 문자열을 그대로 매핑한다', () {
      expect(
        resolveNotificationItemRoute(
          relatedResourceType: 'REPORT',
          relatedResourceId: 3,
        ),
        AppRoutes.report('3'),
      );
      expect(
        resolveNotificationItemRoute(
          relatedResourceType: 'DRAWING_SESSION',
          relatedResourceId: 4,
        ),
        AppRoutes.activityDetail('4'),
      );
      expect(
        resolveNotificationItemRoute(
          relatedResourceType: 'POST',
          relatedResourceId: 5,
        ),
        AppRoutes.communityPost('5'),
      );
    });

    test('계약에 없는 유형은 라우트를 정하지 않는다', () {
      // 임의 화면으로 보내지 않고 호출자가 알림함 목록을 기본값으로 삼는다.
      expect(
        resolveNotificationItemRoute(
          relatedResourceType: 'UNKNOWN_RESOURCE',
          relatedResourceId: 9,
        ),
        isNull,
      );
    });

    test('연결 자원이 없으면 라우트를 정하지 않는다', () {
      expect(
        resolveNotificationItemRoute(
          relatedResourceType: null,
          relatedResourceId: null,
        ),
        isNull,
      );
    });

    test('푸시와 알림함이 같은 자원에 대해 같은 라우트를 만든다', () {
      expect(
        resolveNotificationItemRoute(
          relatedResourceType: 'REPORT',
          relatedResourceId: 55,
        ),
        resolvePushRoute(
          message(resourceType: PushResourceType.report, resourceId: 55),
        ),
      );
    });
  });

  group('resolvePushRoute', () {
    test('연결 자원이 없으면 알림함 목록으로 보낸다', () {
      expect(resolvePushRoute(message()), AppRoutes.notifications);
    });

    test('게시글 푸시는 커뮤니티 게시글 상세로 보낸다', () {
      expect(
        resolvePushRoute(
          message(resourceType: PushResourceType.post, resourceId: 12),
        ),
        AppRoutes.communityPost('12'),
      );
    });
  });
}
