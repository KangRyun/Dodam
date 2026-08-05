import 'package:flutter/foundation.dart';

/// 보호자 PIN gate의 세션 단위 잠금 해제 상태(S15P11B209-874).
///
/// PIN 검증에 한 번 성공하면 재잠금 트리거 전까지 보호자 전환마다 다시 묻지
/// 않는다. 재잠금 트리거는 두 가지다 — 앱이 백그라운드로 갔다가 돌아올 때,
/// 그리고 아동 모드로 들어갈 때. 어느 쪽도 시간 계산을 하지 않으므로 여기에는
/// 타이머가 없다(서버 잠금 상태는 [GuardianPinController]가 따로 다룬다).
final class GuardianUnlockController extends ChangeNotifier {
  bool _isUnlocked = false;

  bool get isUnlocked => _isUnlocked;

  void unlock() => _set(true);

  void lock() => _set(false);

  void _set(bool value) {
    if (_isUnlocked == value) return;
    _isUnlocked = value;
    notifyListeners();
  }

  @override
  String toString() => 'GuardianUnlockController(isUnlocked: $_isUnlocked)';
}
