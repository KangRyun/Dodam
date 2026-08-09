import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/design_system.dart';

/// 하단 탭 하나가 품는 것: 탭 바에 보일 정보와, 그 탭의 첫 화면.
class GuardianShellTab {
  const GuardianShellTab({required this.item, required this.builder});

  final AppBottomTabItem item;

  /// 탭의 뿌리 화면. 아직 준비되지 않은 탭은 자리표시자를 넘겨 두고,
  /// 담당 화면이 완성되면 이 한 줄만 바꾸면 된다.
  final WidgetBuilder builder;
}

/// 보호자 모드의 하단 탭 셸.
///
/// 탭마다 **독립된 [Navigator]** 를 두고 [IndexedStack]으로 겹쳐 둔다.
/// - 독립 Navigator: 기록 탭에서 상세로 들어간 뒤 홈 탭에 다녀와도 그 탭의
///   뒤로가기 스택이 그대로 남는다.
/// - IndexedStack: 보이지 않는 탭도 위젯 트리에 살아 있어 스크롤 위치·입력값
///   같은 화면 상태가 유지된다. 조건부 렌더링으로 바꾸면 매번 초기화된다.
class GuardianShell extends StatefulWidget {
  const GuardianShell({
    required this.tabs,
    this.routeFactory,
    this.initialIndex = 0,
    super.key,
  });

  final List<GuardianShellTab> tabs;

  /// 탭 안에서 다른 화면으로 이동할 때 쓸 라우트 생성기.
  ///
  /// 앱 전체와 같은 주입값을 그대로 쓰기 위해 `AppRouter`의 생성기를 그대로
  /// 넘겨받는다. 넘기지 않으면 탭 뿌리 화면만 열 수 있다.
  final RouteFactory? routeFactory;

  final int initialIndex;

  @override
  State<GuardianShell> createState() => _GuardianShellState();
}

class _GuardianShellState extends State<GuardianShell> {
  late int _index = widget.initialIndex.clamp(0, widget.tabs.length - 1);
  late final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    for (var i = 0; i < widget.tabs.length; i++) GlobalKey<NavigatorState>(),
  ];

  /// 한 번이라도 연 탭. 열지 않은 탭은 만들지 않는다.
  ///
  /// [IndexedStack]은 자식을 모두 만들어 두므로, 그대로 두면 열어 보지도 않은
  /// 탭이 첫 화면부터 서버를 조회한다. 게다가 그 조회는 아직 아이를 고르기
  /// 전에 일어나 "선택된 아이 없음" 상태로 굳는다. 처음 열 때 만들고, 그
  /// 뒤로는 [IndexedStack]이 살려 둔다.
  late final Set<int> _visited = {_index};

  /// 한 번 더 누르면 앱을 닫는 상태인지. 뒤로가기 한 번에 앱이 꺼지면
  /// 실수로 활동 중이던 화면을 잃는다.
  bool _exitArmed = false;
  Timer? _exitTimer;

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index == _index) {
      // 이미 보고 있는 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다.
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  /// 뒤로가기 처리 순서: 탭 안 → 첫 탭 → 종료 확인.
  void _handleBack() {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }

    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }

    _confirmExit();
  }

  void _confirmExit() {
    // iOS에는 하드웨어 뒤로가기가 없고, 앱이 스스로 종료하는 동작은 권장되지
    // 않는다. 첫 탭의 뿌리에서는 아무 일도 일어나지 않는 것이 맞다.
    if (Theme.of(context).platform != TargetPlatform.android) return;

    if (_exitArmed) {
      _exitTimer?.cancel();
      SystemNavigator.pop();
      return;
    }

    _exitArmed = true;
    showAppMessage(context, message: '한 번 더 누르면 앱이 닫혀요');
    _exitTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _exitArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // 뒤로가기를 시스템에 넘기지 않고 항상 셸이 먼저 판단한다.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      _handleBack();
    },
    child: Scaffold(
      backgroundColor: AppColors.canvas,
      body: IndexedStack(
        index: _index,
        children: [
          // 자리는 항상 채운다 — 건너뛰면 IndexedStack의 색인과 탭 번호가 어긋난다.
          for (var i = 0; i < widget.tabs.length; i++)
            if (_visited.contains(i))
              _TabNavigator(
                navigatorKey: _navigatorKeys[i],
                tab: widget.tabs[i],
                routeFactory: widget.routeFactory,
              )
            else
              const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: AppBottomTabBar(
        items: [for (final tab in widget.tabs) tab.item],
        selectedIndex: _index,
        onSelected: _onTabSelected,
      ),
    ),
  );
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.tab,
    required this.routeFactory,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final GuardianShellTab tab;
  final RouteFactory? routeFactory;

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    onGenerateRoute: (settings) {
      if (settings.name == Navigator.defaultRouteName) {
        return MaterialPageRoute<void>(settings: settings, builder: tab.builder);
      }
      return routeFactory?.call(settings) ?? _unknown(settings);
    },
  );

  Route<void> _unknown(RouteSettings settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (context) => Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppTopBar(
        title: '페이지를 찾을 수 없어요',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: const SafeArea(
        child: AppErrorView(
          title: '페이지를 찾을 수 없어요',
          message: '요청한 화면이 없거나 이동 경로가 올바르지 않아요.',
        ),
      ),
    ),
  );
}
