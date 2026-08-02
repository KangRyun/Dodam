import 'dart:async';

import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/app/widgets/guardian_sidebar_shell.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/child/data/repositories/mock_child_repository.dart';
import 'package:dodam/features/notification/application/notification_badge_controller.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/presentation/screens/notification_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 알림함 화면의 읽음 처리가 사이드바 배지에 반영되는지 확인한다.
void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required NotificationInboxRepository repository,
    required NotificationBadgeController badgeController,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListScreen(
          repository: repository,
          badgeController: badgeController,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 이동이 일어나는 알림을 띄우고, 화면이 밀어 올린 라우트 이름을 모아 돌려준다.
  ///
  /// 연결 자원이 있는 카드는 읽음 처리(배지)와 화면 이동을 함께 일으킨다
  /// (S15P11B209-501 + 502). 두 기능이 각자의 브랜치에서만 검증돼 합쳐진 경로는
  /// 여기서 처음 확인한다.
  Future<List<String?>> pumpScreenWithRoutes(
    WidgetTester tester, {
    required NotificationInboxRepository repository,
    required NotificationBadgeController badgeController,
  }) async {
    final pushedRoutes = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListScreen(
          repository: repository,
          badgeController: badgeController,
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

  testWidgets('상세로 이동하는 알림도 배지를 1 줄인다', (tester) async {
    final repository = _FakeInbox([
      _unreadWithResource(1, '분석이 끝났어요', 'REPORT', 3),
      _unread(2, '리포트가 왔어요'),
    ]);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 2);

    final pushedRoutes = await pumpScreenWithRoutes(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    // 감산이 `_markRead`의 mounted 확인보다 앞에 있어야 성립한다. 뒤로 밀리면
    // 이동으로 목록이 가려진 사이 응답이 도착해 배지가 갱신되지 않는다.
    expect(pushedRoutes, [AppRoutes.report('3')]);
    expect(badgeController.value, 1);
  });

  testWidgets('이동하는 알림의 읽음 처리가 실패하면 배지는 그대로다', (tester) async {
    final repository = _FakeInbox([
      _unreadWithResource(1, '분석이 끝났어요', 'REPORT', 3),
    ], markReadFailure: StateError('read failed'));
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 1);

    final pushedRoutes = await pumpScreenWithRoutes(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    // 읽음 실패는 이동을 막지 않지만(501), 배지를 줄이지도 않는다(502).
    expect(pushedRoutes, [AppRoutes.report('3')]);
    expect(badgeController.value, 1);
  });

  testWidgets('이동한 뒤 늦게 도착한 읽음 응답도 배지에 한 번만 반영된다', (tester) async {
    final repository = _FakeInbox([
      _unreadWithResource(1, '분석이 끝났어요', 'REPORT', 3),
      _unread(2, '리포트가 왔어요'),
    ]);
    final gate = Completer<void>();
    repository.markReadGate = gate;
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 2);

    final pushedRoutes = await pumpScreenWithRoutes(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    // `_handleCardTap`이 읽음 처리를 unawaited로 띄우므로 이동은 응답을 기다리지
    // 않는다. 배지는 응답이 와야 움직인다.
    expect(pushedRoutes, [AppRoutes.report('3')]);
    expect(badgeController.value, 2);

    gate.complete();
    await tester.pumpAndSettle();

    expect(repository.markReadCalls, [1]);
    expect(badgeController.value, 1);
  });

  testWidgets('알림 하나를 읽으면 배지가 1 줄어든다', (tester) async {
    final repository = _FakeInbox([
      _unread(1, '분석이 끝났어요'),
      _unread(2, '리포트가 왔어요'),
    ]);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 2);

    await pumpScreen(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(badgeController.value, 1);
  });

  testWidgets('이미 읽은 알림을 다시 눌러도 배지는 그대로다', (tester) async {
    final repository = _FakeInbox([
      _unread(1, '분석이 끝났어요'),
      _read(2, '리포트가 왔어요'),
    ], unreadTotal: 1);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 1);

    await pumpScreen(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.text('리포트가 왔어요'));
    await tester.pumpAndSettle();

    // 읽음 처리는 멱등이지만(계약 §6) 이미 읽은 건은 미열람 수에 없었다.
    expect(badgeController.value, 1);
    expect(repository.markReadCalls, isEmpty);
  });

  testWidgets('모두 읽음은 서버가 알려준 updatedCount만큼 배지를 줄인다', (tester) async {
    // 화면에 올라온 건수가 아니라 서버 처리 건수를 쓴다(계약 §6.5).
    final repository = _FakeInbox(
      [_unread(1, '분석이 끝났어요')],
      unreadTotal: 5,
      updatedCount: 5,
    );
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 5);

    await pumpScreen(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.byKey(const ValueKey('mark-all-read')));
    await tester.pumpAndSettle();

    expect(badgeController.value, 0);
  });

  testWidgets('읽음 처리가 실패하면 배지를 줄이지 않는다', (tester) async {
    final repository = _FakeInbox([
      _unread(1, '분석이 끝났어요'),
    ], markReadFailure: StateError('network down'));
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await badgeController.refresh();
    expect(badgeController.value, 1);

    await pumpScreen(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(badgeController.value, 1);
  });

  testWidgets('같은 알림을 연달아 눌러도 배지는 1만 줄어든다', (tester) async {
    // 카드가 들고 있는 항목은 build 시점의 불변 인스턴스라 응답 대기 중에도
    // 미열람으로 보인다. 서버는 멱등이라 1건만 줄므로 배지도 1만 줄어야 한다.
    final repository = _FakeInbox([
      _unread(1, '분석이 끝났어요'),
      _unread(2, '리포트가 왔어요'),
    ]);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);

    await pumpScreen(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    expect(badgeController.value, 2);

    repository.markReadGate = Completer<void>();
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pump();
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pump();
    repository.markReadGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.markReadCalls, [1]);
    expect(badgeController.value, 1);
  });

  testWidgets('당겨서 새로고침하면 배지도 서버 값으로 다시 센다', (tester) async {
    // IndexedStack이 탭을 살려 두어 재진입으로는 initState가 돌지 않는다.
    // 목록을 다시 받는 지점이 어긋난 배지를 되돌릴 창구가 되어야 한다.
    final repository = _FakeInbox([_unread(1, '분석이 끝났어요')], unreadTotal: 1);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);

    await pumpScreen(
      tester,
      repository: repository,
      badgeController: badgeController,
    );
    expect(badgeController.value, 1);

    repository.unreadTotal = 4;
    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await tester.pumpAndSettle();

    expect(badgeController.value, 4);
  });

  testWidgets('보호자 홈 알림 탭은 선택될 때 배지를 다시 세도록 배선돼 있다', (tester) async {
    final repository = _FakeInbox([_unread(1, '분석이 끝났어요')], unreadTotal: 1);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    final childController = GuardianChildController(
      const MockChildRepository(),
    );
    addTearDown(childController.dispose);

    final route =
        AppRouter.onGenerateRoute(
              const RouteSettings(name: AppRoutes.guardianHome),
              childController: childController,
              notificationInboxRepository: repository,
              notificationBadgeController: badgeController,
            )
            as MaterialPageRoute<void>;

    late GuardianSidebarShell shell;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            shell = route.builder(context) as GuardianSidebarShell;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final notificationTab = shell.destinations.firstWhere(
      (destination) => destination.label == '알림',
    );
    expect(notificationTab.badgeCount, same(badgeController));
    expect(notificationTab.onSelected, isNotNull);

    notificationTab.onSelected!();
    await tester.pumpAndSettle();

    expect(repository.badgeQueries, 1);
    expect(badgeController.value, 1);
  });

  testWidgets('배지 컨트롤러를 주지 않아도 목록은 동작한다', (tester) async {
    final repository = _FakeInbox([_unread(1, '분석이 끝났어요')]);

    await tester.pumpWidget(
      MaterialApp(home: NotificationListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(repository.markReadCalls, [1]);
  });
}

final class _FakeInbox implements NotificationInboxRepository {
  _FakeInbox(
    this.items, {
    int? unreadTotal,
    this.updatedCount = 1,
    this.markReadFailure,
  }) : unreadTotal = unreadTotal ?? items.where((item) => !item.isRead).length;

  final List<NotificationItemDto> items;
  int unreadTotal;
  final int updatedCount;
  final Object? markReadFailure;
  final List<int> markReadCalls = [];

  /// 세워 두면 읽음 처리 응답을 붙잡아 "응답 대기 중" 상태를 만든다.
  Completer<void>? markReadGate;

  final List<NotificationFilterDto> queries = [];

  /// 배지 조회(계약 §0.8이 정한 `unreadOnly=true&size=1`)만 센다.
  int get badgeQueries =>
      queries.where((filter) => filter.unreadOnly && filter.size == 1).length;

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async {
    // 배지 조회(unreadOnly=true&size=1)와 목록 조회를 같은 Fake가 받는다.
    queries.add(filter);
    final visible = filter.unreadOnly
        ? items.where((item) => !item.isRead).take(filter.size).toList()
        : items;
    return ApiPage(
      content: visible,
      page: filter.page,
      size: filter.size,
      totalElements: filter.unreadOnly ? unreadTotal : items.length,
      totalPages: 1,
      hasNext: false,
    );
  }

  @override
  Future<NotificationReadDto> markRead(int notificationId) async {
    markReadCalls.add(notificationId);
    await markReadGate?.future;
    final failure = markReadFailure;
    if (failure != null) throw failure;
    return NotificationReadDto(
      notificationId: notificationId,
      readAt: '2026-07-26T12:00:00',
    );
  }

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) async =>
      NotificationReadAllDto(
        updatedCount: updatedCount,
        readAt: '2026-07-26T12:00:00',
      );
}

NotificationItemDto _unread(int id, String title) => _item(id, title, null);

/// 연결 자원이 있는 미열람 알림. 카드를 누르면 읽음 처리와 함께 상세로 이동한다.
NotificationItemDto _unreadWithResource(
  int id,
  String title,
  String resourceType,
  int resourceId,
) => _item(
  id,
  title,
  null,
  relatedResourceType: resourceType,
  relatedResourceId: resourceId,
);

NotificationItemDto _read(int id, String title) =>
    _item(id, title, '2026-07-26T11:00:00');

NotificationItemDto _item(
  int id,
  String title,
  String? readAt, {
  String? relatedResourceType,
  int? relatedResourceId,
}) => NotificationItemDto(
  notificationId: id,
  type: 'ANALYSIS_COMPLETED',
  title: title,
  content: null,
  relatedResourceType: relatedResourceType,
  relatedResourceId: relatedResourceId,
  data: const {},
  deliveryStatus: 'SENT',
  readAt: readAt,
  sentAt: null,
  createdAt: '2026-07-26T10:00:00',
);
