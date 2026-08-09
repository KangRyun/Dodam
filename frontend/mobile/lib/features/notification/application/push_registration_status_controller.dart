import 'package:flutter/foundation.dart';

import '../domain/failures/push_token_registration_failure.dart';

/// 이 기기·이 계정이 푸시를 받을 수 있는 상태인지 보관한다.
///
/// 디바이스 Token 등록(NOTI-01)이 거절되면 서버는 이 계정으로 푸시를 보내지
/// 않는다. 그 사실을 화면이 알 수 없으면 보호자는 "알림이 안 온다"만 겪고
/// 이유를 모른다. 등록 결과를 한곳에 모아 보호자 화면이 구독하게 한다.
///
/// 아동 화면은 이 상태를 읽지 않는다 — 안내는 보호자 화면에서만 표시한다
/// (아이가 보는 화면을 알림 경고가 덮으면 안 된다).
final class PushRegistrationStatusController extends ChangeNotifier
    implements ValueListenable<PushTokenRegistrationFailure?> {
  PushTokenRegistrationFailure? _failure;
  bool _disposed = false;

  /// 마지막으로 확인된 등록 거절. 정상이거나 아직 시도하지 않았으면 `null`이다.
  @override
  PushTokenRegistrationFailure? get value => _failure;

  /// 보호자에게 알릴 등록 실패가 있는지.
  bool get hasFailure => _failure != null;

  /// 등록 결과를 반영한다. 성공([failure]가 `null`)이면 남아 있던 경고를 지운다.
  ///
  /// Token 갱신·재로그인 때 등록이 다시 성공하면 경고가 저절로 사라져야 한다.
  void report(PushTokenRegistrationFailure? failure) => _set(failure);

  /// 보호자가 안내를 닫았다. 같은 상태가 다시 확인되면 또 표시한다.
  void dismiss() => _set(null);

  /// 로그아웃처럼 사용자가 바뀌는 시점에 비운다. 이전 계정의 등록 상태다.
  void clear() => _set(null);

  void _set(PushTokenRegistrationFailure? next) {
    if (_disposed) return;
    // 같은 사유가 다시 확인된 경우(Token 갱신마다 같은 409)에는 알리지 않는다.
    if (_failure?.type == next?.type) return;
    _failure = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
