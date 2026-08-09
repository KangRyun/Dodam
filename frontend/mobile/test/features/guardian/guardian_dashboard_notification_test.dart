import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/child/data/repositories/mock_child_repository.dart';
import 'package:dodam/features/guardian/presentation/widgets/guardian_dashboard.dart';
import 'package:dodam/features/notification/application/notification_badge_controller.dart';
import 'package:dodam/features/notification/application/push_registration_status_controller.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/failures/push_token_registration_failure.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/presentation/widgets/notification_popup.dart';
import 'package:dodam/features/notification/presentation/widgets/push_registration_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보호자 대시보드 헤더의 알림 버튼과 푸시 등록 안내(S15P11B209-842).
void main() {
  const dot = ValueKey('guardian-header-dot');

  NotificationItemDto item({int notificationId = 1}) => NotificationItemDto(
    notificationId: notificationId,
    type: 'ANALYSIS_COMPLETED',
    title: '분석이 끝났어요',
    content: '민지의 리포트가 준비됐어요',
    relatedResourceType: null,
    relatedResourceId: null,
    data: const {},
    deliveryStatus: 'SENT',
    readAt: null,
    sentAt: null,
    createdAt: '2026-08-02T10:00:00',
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    NotificationInboxRepository? repository,
    NotificationBadgeController? badgeController,
    PushRegistrationStatusController? pushRegistrationStatus,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final childController = GuardianChildController(
      const MockChildRepository(),
    );
    addTearDown(childController.dispose);
    await childController.loadChildren();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuardianDashboard(
            controller: childController,
            notificationInboxRepository: repository,
            notificationBadgeController: badgeController,
            pushRegistrationStatus: pushRegistrationStatus,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('헤더 알림 버튼을 누르면 그 자리에 최근 알림 팝업이 열린다', (tester) async {
    final repository = _FakeInbox([item()], unreadCount: 1);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();

    await pumpDashboard(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    expect(find.byKey(NotificationPopup.panel), findsNothing);

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();

    expect(find.byKey(NotificationPopup.panel), findsOneWidget);
    expect(find.text('분석이 끝났어요'), findsOneWidget);
  });

  testWidgets('미열람이 있을 때만 알림 점을 켠다', (tester) async {
    final repository = _FakeInbox([item()], unreadCount: 2);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);

    await pumpDashboard(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    // 아직 세지 않았으면 점을 켜지 않는다 — 예전에는 항상 켜져 있었다.
    expect(find.byKey(dot), findsNothing);

    await badgeController.refresh();
    await tester.pumpAndSettle();

    expect(find.byKey(dot), findsOneWidget);
  });

  testWidgets('알림함을 주지 않으면 팝업 대신 안내만 띄운다', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();

    expect(find.byKey(NotificationPopup.panel), findsNothing);
    expect(find.text('로그인 후 알림을 확인할 수 있어요.'), findsOneWidget);
  });

  testWidgets('푸시 등록이 거절되면 대시보드에 안내를 띄우고 닫을 수 있다', (tester) async {
    final repository = _FakeInbox([item()]);
    final status = PushRegistrationStatusController();
    addTearDown(status.dispose);

    await pumpDashboard(
      tester,
      repository: repository,
      pushRegistrationStatus: status,
    );
    expect(find.byKey(PushRegistrationNotice.notice), findsNothing);

    status.report(
      const PushTokenRegistrationFailure(
        type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PushRegistrationNotice.notice), findsOneWidget);
    expect(find.text(PushRegistrationNotice.title), findsOneWidget);
    expect(find.text(PushRegistrationNotice.fallbackHint), findsOneWidget);

    await tester.tap(find.byKey(PushRegistrationNotice.dismissAction));
    await tester.pumpAndSettle();

    expect(find.byKey(PushRegistrationNotice.notice), findsNothing);
  });

  testWidgets('암호화 키 미구성(503)도 같은 안내로 알린다', (tester) async {
    final status = PushRegistrationStatusController()
      ..report(
        const PushTokenRegistrationFailure(
          type: PushTokenRegistrationFailureType.storageUnavailable,
        ),
      );
    addTearDown(status.dispose);

    await pumpDashboard(tester, pushRegistrationStatus: status);

    expect(find.byKey(PushRegistrationNotice.notice), findsOneWidget);
  });
}

final class _FakeInbox implements NotificationInboxRepository {
  _FakeInbox(this.items, {this.unreadCount = 0});

  final List<NotificationItemDto> items;
  final int unreadCount;

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async => ApiPage(
    content: filter.unreadOnly ? const [] : items,
    page: 0,
    size: filter.size,
    totalElements: filter.unreadOnly ? unreadCount : items.length,
    totalPages: items.isEmpty ? 0 : 1,
    hasNext: false,
  );

  @override
  Future<NotificationReadDto> markRead(int notificationId) async =>
      NotificationReadDto(
        notificationId: notificationId,
        readAt: DateTime.now().toIso8601String(),
      );

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) async =>
      NotificationReadAllDto(
        updatedCount: items.length,
        readAt: DateTime.now().toIso8601String(),
      );
}
