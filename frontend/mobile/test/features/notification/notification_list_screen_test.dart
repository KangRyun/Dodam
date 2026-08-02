import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/presentation/screens/notification_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotificationItemDto item({
    int notificationId = 1,
    String title = '분석이 끝났어요',
    String? relatedResourceType,
    int? relatedResourceId,
  }) => NotificationItemDto(
    notificationId: notificationId,
    type: 'ANALYSIS_COMPLETED',
    title: title,
    content: '민지의 리포트가 준비됐어요',
    relatedResourceType: relatedResourceType,
    relatedResourceId: relatedResourceId,
    data: const {},
    deliveryStatus: 'SENT',
    readAt: null,
    sentAt: null,
    createdAt: '2026-07-28T10:00:00',
  );

  /// 알림함 화면을 띄우고, 이 화면이 밀어 올린 라우트 이름을 모아 돌려준다.
  Future<List<String?>> pumpScreen(
    WidgetTester tester,
    _FakeNotificationInboxRepository repository,
  ) async {
    final pushedRoutes = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListScreen(repository: repository),
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

  testWidgets('서버에서 받은 알림 목록과 읽지 않음 상태를 표시한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      item(relatedResourceType: 'REPORT', relatedResourceId: 3),
    ]);

    await pumpScreen(tester, repository);

    expect(find.text('분석이 끝났어요'), findsOneWidget);
    expect(find.text('민지의 리포트가 준비됐어요'), findsOneWidget);
    final markAllRead = tester.widget<TextButton>(
      find.byKey(const ValueKey('mark-all-read')),
    );
    expect(markAllRead.onPressed, isNotNull);
  });

  testWidgets('서버 알림이 없으면 빈 상태를 표시한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([]);

    await pumpScreen(tester, repository);

    expect(find.text('아직 알림이 없어요'), findsOneWidget);
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
}

final class _FakeNotificationInboxRepository
    implements NotificationInboxRepository {
  _FakeNotificationInboxRepository(this.items, {this.markReadFails = false});

  final List<NotificationItemDto> items;
  final bool markReadFails;
  final List<int> markReadCalls = [];

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async => ApiPage(
    content: items,
    page: 0,
    size: 20,
    totalElements: items.length,
    totalPages: items.isEmpty ? 0 : 1,
    hasNext: false,
  );

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
  Future<NotificationReadAllDto> markAllRead({String? type}) async =>
      NotificationReadAllDto(
        updatedCount: items.length,
        readAt: DateTime.now().toIso8601String(),
      );
}
