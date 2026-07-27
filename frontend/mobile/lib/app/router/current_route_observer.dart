import 'package:flutter/widgets.dart';

/// 최상단 라우트 이름을 추적한다.
///
/// 푸시가 아동 모드 화면을 덮지 않게 판정하려면(계약 §4.4) 지금 어떤 화면인지
/// 알아야 하는데, `Navigator`는 현재 라우트를 밖에서 물어볼 방법을 주지 않는다.
final class CurrentRouteObserver extends NavigatorObserver {
  String? _currentRouteName;

  String? get currentRouteName => _currentRouteName;

  /// 아동 모드 화면 여부다. 아동 모드 라우트는 모두 `/child/`로 시작한다.
  bool get isChildModeActive =>
      _currentRouteName?.startsWith('/child/') ?? false;

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _currentRouteName = route.settings.name ?? _currentRouteName;
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    _currentRouteName = newRoute?.settings.name ?? _currentRouteName;
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    _currentRouteName = previousRoute?.settings.name;
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    _currentRouteName = previousRoute?.settings.name ?? _currentRouteName;
  }
}
