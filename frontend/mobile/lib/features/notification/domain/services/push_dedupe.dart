import '../entities/push_message.dart';

/// 같은 알림이 두 번 표시되지 않게 최근 `notificationId`를 기억한다.
///
/// 포그라운드 수신과 OS 재전달이 겹치면 같은 메시지가 여러 번 도착한다. 계약
/// (§4.3)상 같은 `notificationId`는 한 번만 표시한다.
///
/// 프로세스 수명 동안만 유지한다. 앱을 다시 켜면 비므로 재표시가 가능하지만,
/// 알림함이 원본을 갖고 있어 사용자가 잃는 정보는 없다.
final class PushDedupe {
  PushDedupe({int capacity = _defaultCapacity})
    : assert(capacity > 0, 'capacity must be positive'),
      _capacity = capacity;

  static const _defaultCapacity = 64;

  final int _capacity;

  /// 삽입 순서를 유지하는 Set이다. 가장 오래된 항목부터 밀어낸다.
  final _seen = <int>{};

  /// 처음 본 알림이면 `true`를 돌려주고 기억한다. 이미 본 알림이면 `false`다.
  bool shouldShow(PushMessage message) {
    if (!_seen.add(message.notificationId)) return false;

    if (_seen.length > _capacity) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  void clear() => _seen.clear();
}
