import 'package:flutter/widgets.dart';

import 'navigation_tap_guard.dart';

/// 화면 이동 진입점.
///
/// `Navigator.of(context).pushNamed(...)`를 화면마다 직접 부르면 연속 탭
/// 방지를 한 곳에서 걸 수 없다. 이동은 모두 여기를 지나게 해서 중복 판정을
/// 한 군데에 모은다.
abstract final class AppNavigation {
  /// 중복 이동을 막으며 화면을 연다.
  ///
  /// 막힌 경우 `null`을 돌려준다. 호출부는 대개 결과를 쓰지 않으므로 예외를
  /// 던지지 않고 조용히 넘긴다 — 사용자 입장에서는 "두 번째 탭이 무시됐다"가
  /// 기대 동작이다.
  ///
  /// [rootNavigator]가 참이면 탭 안이 아니라 앱 최상단 스택에 쌓는다.
  /// 아동 모드처럼 하단 탭이 보이면 안 되는 전체화면 이동에 쓴다.
  static Future<T?>? pushNamed<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    bool rootNavigator = false,
    NavigationTapGuard? guard,
  }) => pushNamedOn<T>(
    Navigator.of(context, rootNavigator: rootNavigator),
    routeName,
    arguments: arguments,
    currentRouteName: ModalRoute.of(context)?.settings.name,
    guard: guard,
  );

  /// [BuildContext] 없이 [NavigatorState]를 직접 들고 이동한다.
  ///
  /// 푸시 알림 클릭처럼 위젯 밖에서 시작되는 이동은 붙잡을 `context`가 없어
  /// `Navigator`를 직접 부르기 쉬운데, 그러면 같은 목적지가 화면 위에 겹쳐
  /// 쌓인다. 이쪽으로 들어오면 화면에서 시작한 이동과 **같은 판정기**를 쓰므로
  /// 두 경로가 같은 상황에서 같게 동작한다.
  ///
  /// [currentRouteName]은 지금 보이는 화면의 라우트 이름이다. `NavigatorObserver`
  /// (`CurrentRouteObserver`)로 얻어 넘긴다. 주지 않으면 "이미 그 화면인지"는
  /// 판정하지 못하고 연속 탭만 걸러진다.
  static Future<T?>? pushNamedOn<T extends Object?>(
    NavigatorState navigator,
    String routeName, {
    Object? arguments,
    String? currentRouteName,
    NavigationTapGuard? guard,
  }) {
    final tapGuard = guard ?? guardFor(navigator);
    final allowed = tapGuard.shouldAllow(
      routeName,
      currentRouteName: currentRouteName,
    );
    if (!allowed) return null;

    return navigator.pushNamed<T>(routeName, arguments: arguments);
  }

  /// 스택을 비우고 이동한다. 로그인·홈 복귀처럼 "여기서 다시 시작" 성격의
  /// 이동에 쓴다. 스택을 비우므로 중복이 쌓일 수 없어 판정하지 않는다.
  static void resetTo(
    BuildContext context,
    String routeName, {
    Object? arguments,
    bool rootNavigator = true,
  }) => resetToOn(
    Navigator.of(context, rootNavigator: rootNavigator),
    routeName,
    arguments: arguments,
  );

  /// [BuildContext] 없이 스택을 비우고 이동한다.
  ///
  /// 앱 생명주기 전환처럼 위젯 밖에서 시작되는 이동에 쓴다([pushNamedOn]과 같은
  /// 이유다). 화면에서 시작한 [resetTo]와 같은 자리를 지나 판정기도 함께
  /// 비워진다.
  static void resetToOn(
    NavigatorState navigator,
    String routeName, {
    Object? arguments,
  }) {
    // 스택이 비워지면 직전 이동 기록은 의미가 없다. 남겨 두면 새 스택의 첫
    // 이동이 근거 없이 막힌다.
    guardFor(navigator).reset();
    navigator.pushNamedAndRemoveUntil(
      routeName,
      (route) => false,
      arguments: arguments,
    );
  }

  /// 해당 Navigator 전용 판정기를 얻는다. 없으면 만들어 붙인다.
  static NavigationTapGuard guardFor(NavigatorState navigator) =>
      navigationTapGuards[navigator] ??= NavigationTapGuard();
}
