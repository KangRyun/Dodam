import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/notification/application/notification_badge_controller.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/presentation/screens/notification_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotificationItemDto item({
    int notificationId = 1,
    String title = '분석이 끝났어요',
    String? content = '민지의 리포트가 준비됐어요',
    String type = 'ANALYSIS_COMPLETED',
    String? relatedResourceType,
    int? relatedResourceId,
    String? readAt,
  }) => NotificationItemDto(
    notificationId: notificationId,
    type: type,
    title: title,
    content: content,
    relatedResourceType: relatedResourceType,
    relatedResourceId: relatedResourceId,
    data: const {},
    deliveryStatus: 'SENT',
    readAt: readAt,
    sentAt: null,
    createdAt: '2026-07-28T10:00:00Z',
  );

  Widget screenApp(
    NotificationInboxRepository repository, {
    NotificationBadgeController? badgeController,
    double textScale = 1,
    List<String?>? pushedRoutes,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: NotificationListScreen(
      repository: repository,
      badgeController: badgeController,
    ),
    onGenerateRoute: (settings) {
      pushedRoutes?.add(settings.name);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: Text('이동한 화면')),
      );
    },
  );

  /// 알림함 화면을 띄우고, 이 화면이 밀어 올린 라우트 이름을 모아 돌려준다.
  Future<List<String?>> pumpScreen(
    WidgetTester tester,
    NotificationInboxRepository repository, {
    NotificationBadgeController? badgeController,
    Size size = const Size(800, 600),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final pushedRoutes = <String?>[];
    await tester.pumpWidget(
      screenApp(
        repository,
        badgeController: badgeController,
        textScale: textScale,
        pushedRoutes: pushedRoutes,
      ),
    );
    await tester.pumpAndSettle();
    return pushedRoutes;
  }

  testWidgets('서버 목록·전령 배너·실제 unread count와 읽음 상태를 표시한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(relatedResourceType: 'REPORT', relatedResourceId: 3),
      item(
        notificationId: 2,
        title: '이미 확인한 소식',
        content: '앞서 확인한 알림이에요',
        readAt: '2026-07-28T11:00:00Z',
      ),
    ]);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);

    await pumpScreen(tester, repository, badgeController: badgeController);

    expect(
      find.byKey(const ValueKey('notification-herald-banner')),
      findsOneWidget,
    );
    expect(find.text('도담이 소식함'), findsOneWidget);
    expect(find.text('새로운 소식이 도착했어요'), findsOneWidget);
    expect(find.bySemanticsLabel('전령 도담이'), findsOneWidget);
    expect(find.text('읽지 않음 1건'), findsOneWidget);
    expect(find.text('분석이 끝났어요'), findsOneWidget);
    expect(find.text('민지의 리포트가 준비됐어요'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('읽지 않은 알림, 분석이 끝났어요')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('읽은 알림, 이미 확인한 소식')), findsOneWidget);
    final unreadSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('읽지 않은 알림, 분석이 끝났어요')),
    );
    expect(
      unreadSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    final markAllRead = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('mark-all-read')),
    );
    expect(markAllRead.onPressed, isNotNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('mark-all-read'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('서버 알림이 없으면 배너와 빈 상태를 함께 표시한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([]);

    await pumpScreen(tester, repository);

    expect(find.text('새로운 소식이 도착했어요'), findsOneWidget);
    expect(find.text('새로운 알림이 없어요'), findsOneWidget);
    expect(find.text('새 소식이 도착하면 이곳에서 알려드릴게요.'), findsOneWidget);
  });

  testWidgets('최초 로딩 상태를 표시한다', (tester) async {
    final repository = _QueuedNotificationInboxRepository();
    await tester.pumpWidget(screenApp(repository));
    await tester.pump();

    expect(find.text('알림을 불러오고 있어요'), findsOneWidget);
    expect(find.text('새로운 소식이 도착했어요'), findsOneWidget);

    repository.requests.single.complete(_page([]));
    await tester.pumpAndSettle();
  });

  testWidgets('최초 조회 오류를 표시하고 재시도한다', (tester) async {
    final repository = _FakeNotificationInboxRepository(
      [],
      loadFailuresRemaining: 1,
    );

    await pumpScreen(tester, repository);

    expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('새로운 알림이 없어요'), findsOneWidget);
    expect(repository.requestedPages, [0, 0]);
  });

  testWidgets('리포트 알림 카드를 누르면 리포트 상세로 이동하고 읽음 처리한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(relatedResourceType: 'REPORT', relatedResourceId: 3),
    ]);

    final pushedRoutes = await pumpScreen(tester, repository);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, [AppRoutes.report('3')]);
    expect(repository.markReadCalls, [1]);
  });

  testWidgets('활동 알림 카드는 활동 상세로 이동한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(relatedResourceType: 'DRAWING_SESSION', relatedResourceId: 42),
    ]);

    final pushedRoutes = await pumpScreen(tester, repository);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, [AppRoutes.activityDetail('42')]);
  });

  testWidgets('게시글 알림 카드는 커뮤니티 게시글 상세로 이동한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(relatedResourceType: 'POST', relatedResourceId: 12),
    ]);

    final pushedRoutes = await pumpScreen(tester, repository);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, [AppRoutes.communityPost('12')]);
  });

  testWidgets('연결 자원이 없는 알림은 읽음 처리만 하고 알림함에 머문다', (tester) async {
    final repository = _FakeNotificationInboxRepository([item()]);

    final pushedRoutes = await pumpScreen(tester, repository);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isEmpty);
    expect(repository.markReadCalls, [1]);
    expect(find.text('분석이 끝났어요'), findsOneWidget);
  });

  testWidgets('읽음 처리가 실패해도 화면 이동은 막지 않는다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(relatedResourceType: 'REPORT', relatedResourceId: 3),
    ], markReadFails: true);

    final pushedRoutes = await pumpScreen(tester, repository);
    await tester.tap(find.text('분석이 끝났어요'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, [AppRoutes.report('3')]);
    expect(find.text('알림을 읽음 처리하지 못했어요.'), findsOneWidget);
  });

  testWidgets('모두 읽음은 실제 state와 unread count를 갱신한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(),
      item(notificationId: 2, title: '새 활동 소식'),
    ]);
    final badgeController = NotificationBadgeController(repository);
    addTearDown(badgeController.dispose);
    await pumpScreen(tester, repository, badgeController: badgeController);

    await tester.tap(find.byKey(const ValueKey('mark-all-read')));
    await tester.pumpAndSettle();

    expect(repository.markAllReadCalls, 1);
    expect(badgeController.value, 0);
    expect(find.text('새 알림 없음'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('mark-all-read')))
          .onPressed,
      isNull,
    );
    expect(find.bySemanticsLabel(RegExp('읽은 알림, 분석이 끝났어요')), findsOneWidget);
  });

  testWidgets('모두 읽음 실패는 기존 카드를 유지하고 오류를 안내한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(),
    ], markAllReadFails: true);
    await pumpScreen(tester, repository);

    await tester.tap(find.byKey(const ValueKey('mark-all-read')));
    await tester.pumpAndSettle();

    expect(repository.markAllReadCalls, 1);
    expect(find.text('전체 읽음 처리에 실패했어요.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('읽지 않은 알림, 분석이 끝났어요')), findsOneWidget);
  });

  testWidgets('모두 읽음 처리 중 연타해도 API를 한 번만 호출한다', (tester) async {
    final gate = Completer<void>();
    final repository = _FakeNotificationInboxRepository([
      item(),
    ], markAllReadGate: gate);
    await pumpScreen(tester, repository);

    await tester.tap(find.byKey(const ValueKey('mark-all-read')));
    await tester.tap(find.byKey(const ValueKey('mark-all-read')));
    await tester.pump();

    expect(repository.markAllReadCalls, 1);
    expect(find.bySemanticsLabel('모두 읽음 처리 중'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('다음 페이지를 불러오며 notificationId 중복을 제거한다', (tester) async {
    final repository = _FakeNotificationInboxRepository(
      const [],
      pages: {
        0: [
          for (var id = 1; id <= 6; id++)
            item(notificationId: id, title: '$id번째 알림'),
        ],
        1: [
          item(notificationId: 6, title: '6번째 알림'),
          item(notificationId: 7, title: '마지막 페이지 알림'),
        ],
      },
    );
    await pumpScreen(tester, repository, size: const Size(844, 390));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
    await tester.pumpAndSettle();

    expect(repository.requestedPages, containsAllInOrder([0, 1]));
    expect(find.text('6번째 알림'), findsOneWidget);
    expect(find.text('마지막 페이지 알림'), findsOneWidget);
  });

  testWidgets('늦게 도착한 오래된 첫 페이지 응답을 폐기한다', (tester) async {
    final repository = _QueuedNotificationInboxRepository();
    await tester.pumpWidget(screenApp(repository));
    await tester.pump();
    expect(repository.requests, hasLength(1));

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final refreshFuture = refresh.onRefresh();
    await tester.pump();
    expect(repository.requests, hasLength(2));

    repository.requests[1].complete(
      _page([item(notificationId: 2, title: '최신 알림')]),
    );
    await refreshFuture;
    await tester.pump();
    repository.requests[0].complete(
      _page([item(notificationId: 1, title: '오래된 알림')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('최신 알림'), findsOneWidget);
    expect(find.text('오래된 알림'), findsNothing);
  });

  const viewports = [Size(1280, 800), Size(844, 390), Size(390, 844)];
  for (final viewport in viewports) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${viewport.width.toInt()}×${viewport.height.toInt()} text scale $scale에서 overflow가 없다',
        (tester) async {
          final repository = _FakeNotificationInboxRepository([
            item(title: '첫 번째 알림'),
            item(notificationId: 2, title: '두 번째 알림'),
            item(notificationId: 3, title: '마지막 알림'),
          ]);
          final badgeController = NotificationBadgeController(repository);
          addTearDown(badgeController.dispose);

          await pumpScreen(
            tester,
            repository,
            badgeController: badgeController,
            size: viewport,
            textScale: scale,
          );

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('notification-trumpeter-frame')),
            findsOneWidget,
          );
          expect(find.text('읽지 않음 3건'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('마지막 알림'),
            300,
            scrollable: find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('마지막 알림'), findsOneWidget);
        },
      );
    }
  }
}

NotificationPage _page(
  List<NotificationItemDto> items, {
  int page = 0,
  bool hasNext = false,
}) => ApiPage(
  content: items,
  page: page,
  size: 20,
  totalElements: items.length,
  totalPages: hasNext ? page + 2 : (items.isEmpty ? 0 : page + 1),
  hasNext: hasNext,
);

final class _FakeNotificationInboxRepository
    implements NotificationInboxRepository {
  _FakeNotificationInboxRepository(
    this.items, {
    this.markReadFails = false,
    this.markAllReadFails = false,
    this.markAllReadGate,
    this.pages,
    this.loadFailuresRemaining = 0,
  });

  final List<NotificationItemDto> items;
  final bool markReadFails;
  final bool markAllReadFails;
  final Completer<void>? markAllReadGate;
  final Map<int, List<NotificationItemDto>>? pages;
  int loadFailuresRemaining;
  final List<int> markReadCalls = [];
  final List<int> requestedPages = [];
  int markAllReadCalls = 0;

  List<NotificationItemDto> get _allItems => pages == null
      ? items
      : pages!.values
            .expand((pageItems) => pageItems)
            .fold(<int, NotificationItemDto>{}, (known, item) {
              known[item.notificationId] = item;
              return known;
            })
            .values
            .toList();

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async {
    if (filter.unreadOnly) {
      final unread = _allItems.where((item) => !item.isRead).toList();
      return ApiPage(
        content: unread.take(filter.size).toList(),
        page: 0,
        size: filter.size,
        totalElements: unread.length,
        totalPages: unread.isEmpty ? 0 : 1,
        hasNext: false,
      );
    }

    requestedPages.add(filter.page);
    if (loadFailuresRemaining > 0) {
      loadFailuresRemaining -= 1;
      throw StateError('load failed');
    }
    final pageItems = pages?[filter.page] ?? (filter.page == 0 ? items : []);
    final hasNext = pages?.containsKey(filter.page + 1) ?? false;
    return _page(pageItems, page: filter.page, hasNext: hasNext);
  }

  @override
  Future<NotificationReadDto> markRead(int notificationId) async {
    markReadCalls.add(notificationId);
    if (markReadFails) throw StateError('mark read failed');
    return NotificationReadDto(
      notificationId: notificationId,
      readAt: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) async {
    markAllReadCalls += 1;
    if (markAllReadGate case final gate?) await gate.future;
    if (markAllReadFails) throw StateError('mark all read failed');
    return NotificationReadAllDto(
      updatedCount: _allItems.where((item) => !item.isRead).length,
      readAt: DateTime.now().toIso8601String(),
    );
  }
}

final class _QueuedNotificationInboxRepository
    implements NotificationInboxRepository {
  final requests = <Completer<NotificationPage>>[];

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) {
    final request = Completer<NotificationPage>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<NotificationReadDto> markRead(int notificationId) =>
      throw UnimplementedError();

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) =>
      throw UnimplementedError();
}
