import 'package:flutter/foundation.dart';

import '../data/dto/notification_inbox_dtos.dart';
import '../domain/repositories/notification_inbox_repository.dart';

/// 보호자 사이드바 "알림" 항목에 표시할 미열람 알림 수를 보관한다.
///
/// 계약(`docs/api/notification-inbox-contract.md` §0.8)이 목록 응답에
/// `unreadCount` 같은 추가 필드를 두지 않기로 확정했으므로, 미열람 수는 NOTI-03을
/// `unreadOnly=true&size=1`로 호출해 `totalElements`에서 얻는다. 항목 본문은 쓰지
/// 않으니 서버가 만드는 페이지를 가장 작게 요청한다(계약 §5는 `size` 1~100 허용).
final class NotificationBadgeController extends ChangeNotifier
    implements ValueListenable<int> {
  NotificationBadgeController(this._repository);

  /// 수만 세는 조회. 미열람 첫 페이지 1건만 받아 `totalElements`를 읽는다.
  static const _countQuery = NotificationFilterDto(unreadOnly: true, size: 1);

  final NotificationInboxRepository _repository;

  int _unreadCount = 0;
  int _generation = 0;
  bool _isRefreshing = false;
  bool _refreshRequested = false;
  bool _disposed = false;

  /// 미열람 알림 수. 조회 전과 조회 실패 뒤에는 0이라 배지가 숨겨진다.
  @override
  int get value => _unreadCount;

  /// 배지를 그려야 하는지.
  bool get hasUnread => _unreadCount > 0;

  /// 서버에서 미열람 수를 다시 읽는다.
  ///
  /// 실패해도 예외를 던지지 않고 0으로 낮춰 배지를 감춘다. 배지는 알림함으로
  /// 유도하는 부가 표시이고 알림함 화면이 이미 자기 오류를 표시하므로, 레일에서
  /// 오류를 한 번 더 알릴 이유가 없다. 갱신에 실패한 옛 수를 남겨 두면 눌러도
  /// 읽을 알림이 없는 상태가 되므로 감추는 편이 오해가 적다.
  ///
  /// 조회가 진행 중이면 같은 조회를 겹쳐 보내지 않되 요청을 버리지도 않는다.
  /// 마지막 요청 하나로 합쳐 두었다가(coalescing) 진행 중인 조회가 끝난 직후
  /// 다시 한 번 조회한다. 푸시가 연달아 올 때 비행 중 통지를 그냥 버리면 첫
  /// 요청이 떠난 뒤 쌓인 알림이 배지에 반영되지 않아 과소 표시된다.
  Future<void> refresh() async {
    if (_disposed) return;
    if (_isRefreshing) {
      _refreshRequested = true;
      return;
    }

    _isRefreshing = true;
    try {
      do {
        _refreshRequested = false;
        await _fetchCount();
      } while (_refreshRequested && !_disposed);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _fetchCount() async {
    final generation = _generation;
    try {
      final page = await _repository.getNotifications(filter: _countQuery);
      if (_isCurrent(generation)) _setCount(page.totalElements);
    } on Object {
      if (_isCurrent(generation)) _setCount(0);
    }
  }

  /// 읽음 처리한 건수만큼 배지를 즉시 줄인다.
  ///
  /// NOTI-04·NOTI-05는 클라이언트가 목록을 다시 받지 않고 배지를 갱신할 수 있게
  /// 읽은 시각과 처리 건수를 응답에 담는다(계약 §6·§6.5). 그 값을 그대로 쓰므로
  /// 읽음 처리마다 추가 조회를 하지 않는다.
  ///
  /// 세대를 올려 이 시점 이전에 출발한 조회 결과를 폐기한다. 그 응답은 읽음
  /// 처리 전 서버 스냅샷이라 나중에 도착하면 방금 뺀 수를 되돌려 놓는다.
  void decrementBy(int count) {
    if (_disposed || count <= 0) return;
    _generation += 1;
    _setCount(count >= _unreadCount ? 0 : _unreadCount - count);
  }

  /// 로그아웃처럼 사용자가 바뀌는 시점에 배지를 비운다. 진행 중인 조회 결과도,
  /// 합쳐 두었던 다음 조회 요청도 이전 사용자의 것이므로 버린다.
  void clear() {
    if (_disposed) return;
    _generation += 1;
    _refreshRequested = false;
    _setCount(0);
  }

  void _setCount(int next) {
    if (_unreadCount == next) return;
    _unreadCount = next;
    notifyListeners();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _refreshRequested = false;
    super.dispose();
  }
}
