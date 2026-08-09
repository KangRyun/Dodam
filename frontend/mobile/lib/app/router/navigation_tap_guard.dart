/// 같은 화면이 연속으로 여러 장 쌓이는 것을 막는 판정기.
///
/// 화면 이동은 비동기다. 버튼을 누르면 라우트가 만들어지고 전환 애니메이션이
/// 끝날 때까지 수백 밀리초가 걸린다. 그 사이에 한 번 더 누르면 같은 화면이
/// 두 장 쌓이고, 뒤로가기를 두 번 눌러야 빠져나오게 된다.
///
/// 위젯과 분리해 둔 이유는 시계를 주입해 시간 흐름을 테스트하기 위함이다.
class NavigationTapGuard {
  NavigationTapGuard({
    this.window = const Duration(milliseconds: 600),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 같은 목적지로의 재이동을 막는 시간 폭.
  ///
  /// 기본 전환 애니메이션(약 300ms)보다 넉넉히 잡되, 사용자가 의도적으로
  /// 다시 들어가려는 것을 막을 만큼 길지 않게 둔다.
  final Duration window;
  final DateTime Function() _clock;

  String? _lastRoute;
  DateTime? _lastAt;

  /// [routeName]으로 이동해도 되는지 판단한다.
  ///
  /// [currentRouteName]은 지금 보고 있는 화면의 라우트 이름이다. 같은 곳으로
  /// 다시 가는 요청은 시간과 무관하게 막는다 — 이미 그 화면에 있기 때문이다.
  bool shouldAllow(String routeName, {String? currentRouteName}) {
    if (currentRouteName != null && currentRouteName == routeName) {
      return false;
    }

    final now = _clock();
    if (_lastRoute == routeName &&
        _lastAt != null &&
        now.difference(_lastAt!) < window) {
      return false;
    }

    _lastRoute = routeName;
    _lastAt = now;
    return true;
  }

  /// 화면을 빠져나온 뒤 곧바로 같은 곳으로 다시 들어갈 수 있게 기록을 지운다.
  void reset() {
    _lastRoute = null;
    _lastAt = null;
  }
}

/// Navigator마다 따로 두는 판정기 보관소.
///
/// 앱 전역에 하나만 두면 서로 무관한 스택끼리 판정을 나눠 갖게 된다. 탭마다
/// 스택이 따로인 구조에서는 기록 탭에서 막 이동했다는 이유로 홈 탭의 이동이
/// 막히는 일이 생긴다. Navigator가 사라지면 판정기도 함께 사라진다.
final Expando<NavigationTapGuard> navigationTapGuards = Expando(
  'navigationTapGuard',
);
