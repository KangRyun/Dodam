import 'dart:async';

import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/notification/application/notification_badge_controller.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('미열람 수를 unreadOnly=true&size=1 조회의 totalElements에서 얻는다', () async {
    // 계약 §0.8이 목록 응답에 unreadCount를 두지 않기로 확정했으므로
    // 미열람 수의 출처는 이 조회의 totalElements뿐이다.
    final repository = _FakeInbox(unread: 7);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.value, 7);
    expect(controller.hasUnread, isTrue);
    expect(repository.lastFilter?.unreadOnly, isTrue);
    expect(repository.lastFilter?.size, 1);
    expect(repository.lastFilter?.page, 0);
    expect(repository.lastFilter?.type, isNull);
  });

  test('미열람이 없으면 0이라 배지를 그리지 않는다', () async {
    final controller = NotificationBadgeController(_FakeInbox());
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.value, 0);
    expect(controller.hasUnread, isFalse);
  });

  test('수가 바뀌면 리스너에게 알리고, 같은 수면 알리지 않는다', () async {
    final repository = _FakeInbox(unread: 3);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.refresh();
    expect(notifications, 1);

    await controller.refresh();
    expect(notifications, 1);
  });

  test('조회에 실패하면 오류를 던지지 않고 배지를 감춘다', () async {
    final repository = _FakeInbox(unread: 5);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.value, 5);

    repository.failure = StateError('network down');
    await controller.refresh();

    // 갱신하지 못한 옛 수를 남기면 눌러도 읽을 알림이 없는 상태가 된다.
    expect(controller.value, 0);
    expect(controller.hasUnread, isFalse);
  });

  test('읽음 처리한 건수만큼 재조회 없이 줄인다', () async {
    final repository = _FakeInbox(unread: 4);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    controller.decrementBy(1);
    expect(controller.value, 3);

    controller.decrementBy(2);
    expect(controller.value, 1);
    expect(repository.getCalls, 1);
  });

  test('남은 수보다 많이 줄여도 음수가 되지 않는다', () async {
    final controller = NotificationBadgeController(_FakeInbox(unread: 2));
    addTearDown(controller.dispose);
    await controller.refresh();

    controller.decrementBy(9);

    expect(controller.value, 0);
  });

  test('0 이하로 줄이라는 요청은 무시한다', () async {
    final controller = NotificationBadgeController(_FakeInbox(unread: 2));
    addTearDown(controller.dispose);
    await controller.refresh();

    controller
      ..decrementBy(0)
      ..decrementBy(-3);

    expect(controller.value, 2);
  });

  test('감산보다 먼저 출발한 조회가 나중에 도착해도 감산을 되돌리지 않는다', () async {
    // 포그라운드 복귀로 시작된 조회가 비행 중일 때 사용자가 알림을 읽는 경우다.
    // 그 응답은 읽음 처리 전 스냅샷이라 반영하면 배지가 도로 올라간다.
    final repository = _FakeInbox(unread: 5);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.value, 5);

    repository.gate = Completer<void>();
    final pending = controller.refresh();
    controller.decrementBy(1);
    expect(controller.value, 4);

    repository.gate!.complete();
    await pending;

    expect(controller.value, 4);
  });

  test('전체 읽음 감산도 비행 중이던 조회 결과에 덮이지 않는다', () async {
    final repository = _FakeInbox(unread: 6);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    repository.gate = Completer<void>();
    final pending = controller.refresh();
    controller.decrementBy(6);
    repository.gate!.complete();
    await pending;

    expect(controller.value, 0);
  });

  test('조회 중 들어온 갱신 요청을 버리지 않고 끝난 뒤 한 번만 다시 조회한다', () async {
    // 푸시가 연달아 오면 비행 중 통지가 사라져 배지가 과소 표시되던 경로다.
    final repository = _FakeInbox(unread: 1);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);

    repository.gate = Completer<void>();
    final pending = controller.refresh();
    repository.unread = 3;
    await controller.refresh();
    await controller.refresh();
    repository.gate!.complete();
    await pending;

    expect(controller.value, 3);
    // 세 번 요청했지만 비행 중 둘은 하나로 합쳐 조회는 두 번뿐이다.
    expect(repository.getCalls, 2);
  });

  test('조회 중 요청이 없었으면 다시 조회하지 않는다', () async {
    final repository = _FakeInbox(unread: 2);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);

    repository.gate = Completer<void>();
    final pending = controller.refresh();
    repository.gate!.complete();
    await pending;

    expect(repository.getCalls, 1);
  });

  test('clear는 합쳐 두었던 다음 조회 요청까지 버린다', () async {
    final repository = _FakeInbox(unread: 6);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    repository.gate = Completer<void>();

    final pending = controller.refresh();
    await controller.refresh();
    controller.clear();
    repository.gate!.complete();
    await pending;

    expect(controller.value, 0);
    expect(repository.getCalls, 1);
  });

  test('clear는 배지를 비우고 진행 중이던 조회 결과를 버린다', () async {
    final repository = _FakeInbox(unread: 6);
    final controller = NotificationBadgeController(repository);
    addTearDown(controller.dispose);
    repository.gate = Completer<void>();

    final pending = controller.refresh();
    controller.clear();
    repository.gate!.complete();
    await pending;

    // 로그아웃 뒤에 도착한 이전 사용자의 수를 반영하면 안 된다.
    expect(controller.value, 0);
  });

  test('dispose 뒤 도착한 응답은 notifyListeners를 부르지 않는다', () async {
    final repository = _FakeInbox(unread: 6);
    final controller = NotificationBadgeController(repository);
    repository.gate = Completer<void>();

    final pending = controller.refresh();
    controller.dispose();
    repository.gate!.complete();

    await expectLater(pending, completes);
    expect(controller.value, 0);
  });

  test('dispose 뒤 decrementBy·clear는 아무 일도 하지 않는다', () async {
    final controller = NotificationBadgeController(_FakeInbox(unread: 3));
    await controller.refresh();
    controller.dispose();

    expect(() => controller.decrementBy(1), returnsNormally);
    expect(controller.clear, returnsNormally);
  });
}

final class _FakeInbox implements NotificationInboxRepository {
  _FakeInbox({this.unread = 0});

  int unread;
  Object? failure;
  Completer<void>? gate;
  NotificationFilterDto? lastFilter;
  int getCalls = 0;

  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async {
    getCalls += 1;
    lastFilter = filter;
    // 응답은 요청이 떠난 시점의 서버 상태를 담는다. 비행 중에 상태가 바뀌어도
    // 이미 출발한 응답은 옛 수를 들고 도착한다 — 경합 시나리오의 전제다.
    final snapshot = unread;
    await gate?.future;

    final error = failure;
    if (error != null) throw error;

    return ApiPage(
      content: snapshot == 0
          ? const <NotificationItemDto>[]
          : <NotificationItemDto>[_item],
      page: filter.page,
      size: filter.size,
      totalElements: snapshot,
      totalPages: snapshot,
      hasNext: snapshot > 1,
    );
  }

  @override
  Future<NotificationReadDto> markRead(int notificationId) =>
      throw UnimplementedError();

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) =>
      throw UnimplementedError();
}

const _item = NotificationItemDto(
  notificationId: 900,
  type: 'ANALYSIS_COMPLETED',
  title: '분석이 완료됐어요',
  content: '리포트를 확인해 보세요',
  relatedResourceType: 'REPORT',
  relatedResourceId: 55,
  data: {},
  deliveryStatus: 'SENT',
  readAt: null,
  sentAt: null,
  createdAt: '2026-07-26T10:00:00',
);
