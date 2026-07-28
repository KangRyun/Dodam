import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/presentation/screens/notification_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('서버에서 받은 알림 목록과 읽지 않음 상태를 표시한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([
      const NotificationItemDto(
        notificationId: 1,
        type: 'ANALYSIS_COMPLETED',
        title: '분석이 끝났어요',
        content: '민지의 리포트가 준비됐어요',
        relatedResourceType: 'REPORT',
        relatedResourceId: 3,
        data: {},
        deliveryStatus: 'SENT',
        readAt: null,
        sentAt: null,
        createdAt: '2026-07-28T10:00:00',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: NotificationListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('분석이 끝났어요'), findsOneWidget);
    expect(find.text('민지의 리포트가 준비됐어요'), findsOneWidget);
    final markAllRead = tester.widget<TextButton>(
      find.byKey(const ValueKey('mark-all-read')),
    );
    expect(markAllRead.onPressed, isNotNull);
  });

  testWidgets('서버 알림이 없으면 빈 상태를 표시한다', (tester) async {
    final repository = _FakeNotificationInboxRepository([]);

    await tester.pumpWidget(
      MaterialApp(home: NotificationListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 알림이 없어요'), findsOneWidget);
  });
}

final class _FakeNotificationInboxRepository
    implements NotificationInboxRepository {
  _FakeNotificationInboxRepository(this.items);

  final List<NotificationItemDto> items;

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
