import 'package:flutter/widgets.dart';

/// 최상단 라우트 이름을 추적한다.
///
/// 푸시가 아동 모드 화면을 덮지 않게 판정하려면(계약 §4.4) 지금 어떤 화면인지
/// 알아야 하는데, `Navigator`는 현재 라우트를 밖에서 물어볼 방법을 주지 않는다.
final class CurrentRouteObserver extends NavigatorObserver {
  CurrentRouteObserver({this.onChildModeEntered});

  /// 아동 모드로 **들어설 때** 한 번 알린다(보호자 PIN 재잠금 트리거,
  /// S15P11B209-874). 아동 모드 안에서 화면을 옮겨 다니는 동안에는 다시 부르지
  /// 않는다.
  final VoidCallback? onChildModeEntered;

  String? _currentRouteName;

  String? get currentRouteName => _currentRouteName;

  /// 아동 모드 화면 여부다. 아동 모드 라우트는 모두 `/child/`로 시작한다.
  bool get isChildModeActive => _isChildMode(_currentRouteName);

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _updateCurrent(route.settings.name ?? _currentRouteName);
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    _updateCurrent(newRoute?.settings.name ?? _currentRouteName);
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    _updateCurrent(previousRoute?.settings.name);
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    _updateCurrent(previousRoute?.settings.name ?? _currentRouteName);
  }

  void _updateCurrent(String? routeName) {
    final wasChildMode = isChildModeActive;
    _currentRouteName = routeName;
    if (!wasChildMode && isChildModeActive) onChildModeEntered?.call();
  }

  static bool _isChildMode(String? routeName) =>
      routeName?.startsWith('/child/') ?? false;
}
