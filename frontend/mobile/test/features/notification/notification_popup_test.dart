import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/notification/application/notification_badge_controller.dart';
import 'package:dodam/features/notification/application/push_registration_status_controller.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/failures/push_token_registration_failure.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/presentation/widgets/notification_item_card.dart';
import 'package:dodam/features/notification/presentation/widgets/notification_popup.dart';
import 'package:dodam/features/notification/presentation/widgets/push_registration_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보호자 대시보드 알림 버튼이 여는 최근 알림 팝업(S15P11B209-842).
void main() {
  NotificationItemDto item({
    int notificationId = 1,
    String title = '분석이 끝났어요',
    String? relatedResourceType,
    int? relatedResourceId,
    String? readAt,
  }) => NotificationItemDto(
    notificationId: notificationId,
    type: 'ANALYSIS_COMPLETED',
    title: title,
    content: '민지의 리포트가 준비됐어요',
    relatedResourceType: relatedResourceType,
    relatedResourceId: relatedResourceId,
    data: const {},
    deliveryStatus: 'SENT',
    readAt: readAt,
    sentAt: null,
    createdAt: '2026-08-02T10:00:00',
  );

  /// 태블릿 가로 화면에서 헤더 오른쪽 끝에 놓인 알림 버튼을 흉내낸다.
  const anchor = Rect.fromLTWH(1206, 24, 44, 44);

  /// 팝업 호스트를 세우고 팝업이 고른 이동 대상 라우트를 모아 돌려준다.
  ///
  /// 이동은 팝업이 닫힌 뒤 호출부가 수행한다 — 실제 대시보드와 같은 순서다.
  Future<List<String?>> pumpHost(
    WidgetTester tester, {
    required NotificationInboxRepository repository,
    NotificationBadgeController? badgeController,
    PushRegistrationStatusController? pushRegistrationStatus,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pushedRoutes = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topRight,
              child: TextButton(
                key: const ValueKey('open-popup'),
                onPressed: () async {
                  final route = await showNotificationPopup(
                    context,
                    anchorRect: anchor,
                    repository: repository,
                    badgeController: badgeController,
                    pushRegistrationStatus: pushRegistrationStatus,
                    onDismissPushNotice: pushRegistrationStatus?.dismiss,
                  );
                  if (route == null || !context.mounted) return;
                  await Navigator.of(context).pushNamed(route);
                },
                child: const Text('알림 열기'),
              ),
            ),
          ),
        ),
        onGenerateRoute: (settings) {
          pushedRoutes.add(settings.name);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('이동한 화면')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    return pushedRoutes;
  }

  Future<void> openPopup(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-popup')));
    await tester.pumpAndSettle();
  }

  testWidgets('팝업은 최근 알림 목록과 미열람 수 요약을 보여준다', (tester) async {
    final repository = _FakeInbox([
      item(relatedResourceType: 'REPORT', relatedResourceId: 3),
      item(notificationId: 2, title: '리포트가 왔어요'),
    ], unreadCount: 2);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();

    await pumpHost(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await openPopup(tester);

    expect(find.byKey(NotificationPopup.panel), findsOneWidget);
    expect(find.text('분석이 끝났어요'), findsOneWidget);
    expect(find.text('리포트가 왔어요'), findsOneWidget);
    expect(find.text('읽지 않음 2건'), findsOneWidget);
  });

  testWidgets('팝업은 최근 몇 건만 요청한다', (tester) async {
    final repository = _FakeInbox([item()]);

    await pumpHost(tester, repository: repository);
    await openPopup(tester);

    // 목록 조회는 팝업이 쓰는 요약 크기 하나뿐이다(배지 조회는 별도 필터).
    final listQueries = repository.filters
        .where((filter) => !filter.unreadOnly)
        .toList();
    expect(listQueries, hasLength(1));
    expect(listQueries.single.size, 5);
    expect(listQueries.single.page, 0);
  });

  testWidgets('알림을 누르면 팝업을 닫고 관련 화면으로 이동하며 읽음 처리한다', (tester) async {
    final repository = _FakeInbox([
      item(relatedResourceType: 'REPORT', relatedResourceId: 3),
    ], unreadCount: 1);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 1);

    final pushedRoutes = await pumpHost(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await openPopup(tester);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    // 사이드바 알림함과 같은 매핑 함수·같은 이동 진입점을 쓴다.
    expect(pushedRoutes, [AppRoutes.report('3')]);
    expect(repository.markReadCalls, [1]);
    expect(find.byKey(NotificationPopup.panel), findsNothing);
    expect(badgeController.value, 0);
  });

  testWidgets('연결 자원이 없는 알림은 팝업에 머물고 읽음만 반영한다', (tester) async {
    final repository = _FakeInbox([item()], unreadCount: 1);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();

    final pushedRoutes = await pumpHost(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await openPopup(tester);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isEmpty);
    expect(find.byKey(NotificationPopup.panel), findsOneWidget);
    expect(repository.markReadCalls, [1]);
    final card = tester.widget<NotificationItemCard>(
      find.byKey(const ValueKey('notification-popup-item-1')),
    );
    expect(card.item.isRead, isTrue);
    expect(badgeController.value, 0);
  });

  testWidgets('응답을 기다리는 동안 같은 알림을 다시 눌러도 읽음 처리는 한 번만 보낸다', (tester) async {
    // 왕복이 즉시 끝나면 연타 방지 자체를 확인할 수 없다. 응답을 늦춰 두 번째
    // 탭이 진행 중인 요청과 겹치게 만든다.
    final repository = _FakeInbox(
      [item()],
      unreadCount: 1,
      readDelay: const Duration(milliseconds: 200),
    );

    await pumpHost(tester, repository: repository);
    await openPopup(tester);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(repository.markReadCalls, [1]);
  });

  testWidgets('읽음 처리가 실패하면 팝업에 안내를 남긴다', (tester) async {
    final repository = _FakeInbox([item()], markReadFails: true);

    await pumpHost(tester, repository: repository);
    await openPopup(tester);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(find.text('알림을 읽음 처리하지 못했어요.'), findsOneWidget);
  });

  testWidgets('전체 보기는 사이드바 알림함 라우트로 이동한다', (tester) async {
    final repository = _FakeInbox([item()]);

    final pushedRoutes = await pumpHost(tester, repository: repository);
    await openPopup(tester);
    await tester.tap(find.byKey(NotificationPopup.seeAllAction));
    await tester.pumpAndSettle();

    expect(pushedRoutes, [AppRoutes.notifications]);
    expect(find.byKey(NotificationPopup.panel), findsNothing);
  });

  testWidgets('알림이 없으면 빈 상태를 보여준다', (tester) async {
    final repository = _FakeInbox([]);

    await pumpHost(tester, repository: repository);
    await openPopup(tester);

    expect(find.text('아직 알림이 없어요.'), findsOneWidget);
    expect(find.byKey(NotificationPopup.seeAllAction), findsOneWidget);
  });

  testWidgets('조회에 실패하면 다시 시도할 수 있다', (tester) async {
    final repository = _FakeInbox([item()], failListCalls: 1);

    await pumpHost(tester, repository: repository);
    await openPopup(tester);

    expect(find.text('알림을 불러오지 못했어요.'), findsOneWidget);

    await tester.tap(find.byKey(NotificationPopup.retryAction));
    await tester.pumpAndSettle();

    expect(find.text('분석이 끝났어요'), findsOneWidget);
  });

  testWidgets('팝업을 열면 미열람 배지를 다시 센다', (tester) async {
    final repository = _FakeInbox([item()], unreadCount: 3);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    expect(badgeController.value, 0);

    await pumpHost(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await openPopup(tester);

    // 주기 폴링 없이, 보호자가 알림을 확인하는 순간에 서버 값을 읽는다.
    expect(badgeController.value, 3);
    expect(
      repository.filters.where((filter) => filter.unreadOnly),
      hasLength(1),
    );
  });

  testWidgets('푸시 등록이 거절된 상태는 팝업에도 안내한다', (tester) async {
    final repository = _FakeInbox([item()]);
    final status = PushRegistrationStatusController()
      ..report(
        const PushTokenRegistrationFailure(
          type: PushTokenRegistrationFailureType.claimedByAnotherAccount,
        ),
      );
    addTearDown(status.dispose);

    await pumpHost(
      tester,
      repository: repository,
      pushRegistrationStatus: status,
    );
    await openPopup(tester);

    expect(find.byKey(PushRegistrationNotice.notice), findsOneWidget);
    expect(find.text(PushRegistrationNotice.title), findsOneWidget);

    await tester.tap(find.byKey(PushRegistrationNotice.dismissAction));
    await tester.pumpAndSettle();

    expect(status.hasFailure, isFalse);
    expect(find.byKey(PushRegistrationNotice.notice), findsNothing);
  });

  testWidgets('팝업은 화면 안에 그려진다', (tester) async {
    final repository = _FakeInbox([
      for (var id = 1; id <= 5; id++) item(notificationId: id),
    ]);

    await pumpHost(tester, repository: repository);
    await openPopup(tester);

    final panel = tester.getRect(find.byKey(NotificationPopup.panel));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(panel.left, greaterThanOrEqualTo(0));
    expect(panel.top, greaterThanOrEqualTo(0));
    expect(panel.right, lessThanOrEqualTo(screen.width));
    expect(panel.bottom, lessThanOrEqualTo(screen.height));
    // 버튼 아래에 붙는다.
    expect(panel.top, greaterThanOrEqualTo(anchor.bottom));
  });

  group('NotificationPopupLayout', () {
    const margin = EdgeInsets.all(16);
    const screen = Size(1280, 800);

    test('앵커 아래에 붙이고 오른쪽 끝을 맞춘다', () {
      const layout = NotificationPopupLayout(
        anchorRect: Rect.fromLTWH(1206, 24, 44, 44),
        margin: margin,
      );

      final offset = layout.getPositionForChild(screen, const Size(380, 420));

      expect(offset.dx, 1250 - 380);
      expect(offset.dy, 24 + 44 + 8);
    });

    test('왼쪽으로 넘치면 여백까지만 밀어 넣는다', () {
      const layout = NotificationPopupLayout(
        anchorRect: Rect.fromLTWH(20, 24, 44, 44),
        margin: margin,
      );

      final offset = layout.getPositionForChild(screen, const Size(380, 420));

      expect(offset.dx, margin.left);
    });

    test('아래 공간이 부족하면 앵커 위로 뒤집는다', () {
      const layout = NotificationPopupLayout(
        anchorRect: Rect.fromLTWH(1206, 700, 44, 44),
        margin: margin,
      );

      final offset = layout.getPositionForChild(screen, const Size(380, 420));

      expect(offset.dy, 700 - 8 - 420);
    });

    test('위아래 모두 부족하면 화면 안으로 눌러 담는다', () {
      const layout = NotificationPopupLayout(
        anchorRect: Rect.fromLTWH(1206, 300, 44, 44),
        margin: margin,
      );

      final offset = layout.getPositionForChild(screen, const Size(380, 780));

      // 아래·위 모두 모자라면 위 여백을 지키는 쪽을 택한다.
      expect(offset.dy, margin.top);
    });

    test('좁은 화면에서도 여백 안쪽으로 폭을 줄인다', () {
      const layout = NotificationPopupLayout(
        anchorRect: Rect.fromLTWH(300, 24, 44, 44),
        margin: margin,
      );

      final constraints = layout.getConstraintsForChild(
        const BoxConstraints(maxWidth: 360, maxHeight: 640),
      );

      expect(constraints.maxWidth, 360 - margin.horizontal);
      expect(constraints.maxHeight, lessThanOrEqualTo(640 - margin.vertical));
    });
  });
}

final class _FakeInbox implements NotificationInboxRepository {
  _FakeInbox(
    this.items, {
    this.unreadCount = 0,
    this.markReadFails = false,
    this.failListCalls = 0,
    this.readDelay = Duration.zero,
  });

  final List<NotificationItemDto> items;

  /// 배지 조회(`unreadOnly`)가 돌려줄 미열람 수.
  final int unreadCount;
  final bool markReadFails;

  /// 앞쪽 몇 번의 목록 조회를 실패시킨다(재시도 검증용).
  final int failListCalls;

  /// 읽음 처리 응답을 늦춘다(연타 방지 검증용).
  final Duration readDelay;

  final List<NotificationFilterDto> filters = [];
  final List<int> markReadCalls = [];
  int _listCalls = 0;
  int _readItems = 0;

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async {
    filters.add(filter);
    if (filter.unreadOnly) {
      final remaining = unreadCount - _readItems;
      return ApiPage(
        content: const [],
        page: 0,
        size: filter.size,
        totalElements: remaining < 0 ? 0 : remaining,
        totalPages: 0,
        hasNext: false,
      );
    }

    _listCalls += 1;
    if (_listCalls <= failListCalls) throw StateError('list failed');
    return ApiPage(
      content: items,
      page: 0,
      size: filter.size,
      totalElements: items.length,
      totalPages: items.isEmpty ? 0 : 1,
      hasNext: false,
    );
  }

  @override
  Future<NotificationReadDto> markRead(int notificationId) async {
    markReadCalls.add(notificationId);
    if (readDelay > Duration.zero) await Future<void>.delayed(readDelay);
    if (markReadFails) throw StateError('mark read failed');
    _readItems += 1;
    return NotificationReadDto(
      notificationId: notificationId,
      readAt: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) async =>
      NotificationReadAllDto(
        updatedCount: items.length,
        readAt: DateTime.now().toIso8601String(),
      );
}
