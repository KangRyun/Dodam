import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/guardian/presentation/widgets/guardian_home_theme.dart';

/// 사이드바 셸의 목적지 하나. [builder]는 처음 방문할 때 한 번만 만든다.
class GuardianNavItem {
  const GuardianNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.builder,
    this.routeName,
    this.badgeCount,
    this.onSelected,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final WidgetBuilder builder;

  /// 이 목적지가 대응하는 라우트 이름. 셸은 값을 해석하지 않고
  /// [GuardianSidebarShell.onVisibleRouteChanged]로 그대로 넘기기만 한다
  /// ([label]과 같은 취급이다). 같은 화면을 여는 라우트가 따로 있는 목적지만
  /// 채우면 되고, 나머지는 비워 둔다.
  final String? routeName;

  /// 아이콘 우상단에 표시할 개수. null이거나 값이 0 이하면 배지를 그리지 않는다.
  /// 셸은 개수의 출처를 모르며 값이 바뀌면 해당 항목만 다시 그린다.
  final ValueListenable<int>? badgeCount;

  /// 사용자가 이 목적지를 눌렀을 때 알린다. 셸이 [IndexedStack]으로 방문한 탭을
  /// 살려 두므로 다시 들어와도 화면의 `initState`는 재실행되지 않는다. 재진입
  /// 시점에 스스로 갱신해야 하는 항목이 쓴다. 셸은 무엇을 갱신하는지 모른다.
  final VoidCallback? onSelected;
}

/// 태블릿 보호자 모드의 좌측 사이드바 셸(시안 1:1).
///
/// 흰 레일(104px) — 로고 + 세로 nav + 맨 아래 "프로필 전환". 본문은
/// [IndexedStack]으로 전환(탭 상태 보존). 배경은 따뜻한 크림(warm).
class GuardianSidebarShell extends StatefulWidget {
  const GuardianSidebarShell({
    required this.destinations,
    required this.onSwitchProfile,
    this.onVisibleRouteChanged,
    super.key,
  });

  final List<GuardianNavItem> destinations;
  final void Function(BuildContext context) onSwitchProfile;

  /// 지금 보이는 목적지의 [GuardianNavItem.routeName]을 알린다.
  ///
  /// 탭 전환은 라우트를 쌓지 않아 `Navigator` 관찰자 눈에는 셸 하나만 보인다.
  /// 셸 밖에서 "이미 그 화면인지"를 판정하려면 어느 탭이 떠 있는지 알아야 한다
  /// (S15P11B209-501: 알림 탭을 보는 중에 온 푸시가 알림함을 한 장 더 쌓았다).
  ///
  /// 셸을 만들 때 첫 목적지로 한 번, 이후 보이는 목적지가 바뀔 때마다 부른다.
  /// 셸이 다시 만들어지면 처음부터 다시 알리므로 밖에 남은 값이 뒤처지지 않는다.
  /// 목적지가 [GuardianNavItem.routeName]을 두지 않았으면 `null`을 넘긴다.
  final ValueChanged<String?>? onVisibleRouteChanged;

  @override
  State<GuardianSidebarShell> createState() => _GuardianSidebarShellState();
}

class _GuardianSidebarShellState extends State<GuardianSidebarShell> {
  int _index = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    _notifyVisibleRoute();
  }

  void _select(int index) {
    // 보고 있던 탭을 다시 눌렀을 때도 알린다. 갱신을 바라고 아이콘을 다시 누르는
    // 것도 사용자가 흔히 시도하는 복구 동작이다. 아래 setState만 건너뛴다.
    widget.destinations[index].onSelected?.call();
    if (_index == index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
    _notifyVisibleRoute();
  }

  void _notifyVisibleRoute() =>
      widget.onVisibleRouteChanged?.call(widget.destinations[_index].routeName);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DodamHome.warm,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rail(
              destinations: widget.destinations,
              selectedIndex: _index,
              onSelect: _select,
              onSwitchProfile: widget.onSwitchProfile,
            ),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < widget.destinations.length; i++)
                    _visited.contains(i)
                        ? widget.destinations[i].builder(context)
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.onSwitchProfile,
  });

  final List<GuardianNavItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final void Function(BuildContext context) onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      decoration: const BoxDecoration(
        color: DodamHome.surface,
        border: Border(right: BorderSide(color: DodamHome.line)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < destinations.length; i++)
            _NavButton(
              item: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          _NavButton.action(
            key: const ValueKey('guardian-switch-profile'),
            icon: Icons.chevron_left_rounded,
            label: '프로필 전환',
            onTap: () => onSwitchProfile(context),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required GuardianNavItem this.item,
    required this.selected,
    required this.onTap,
  }) : icon = null,
       label = null;

  const _NavButton.action({
    required IconData this.icon,
    required String this.label,
    required this.onTap,
    super.key,
  }) : item = null,
       selected = false;

  final GuardianNavItem? item;
  final IconData? icon;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resolvedIcon = item == null
        ? icon!
        : (selected ? item!.selectedIcon : item!.icon);
    final resolvedLabel = item?.label ?? label!;
    final fg = selected ? DodamHome.navOn : DodamHome.inkSoft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? DodamHome.pointSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: 72,
            padding: const EdgeInsets.fromLTRB(0, 11, 0, 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavIcon(
                  icon: resolvedIcon,
                  color: fg,
                  badgeCount: item?.badgeCount,
                ),
                const SizedBox(height: 5),
                Text(
                  resolvedLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// nav 아이콘과 우상단 미열람 배지를 겹쳐 그린다. [badgeCount]가 없으면 아이콘만
/// 그리므로 배지를 쓰지 않는 항목은 위젯 트리가 늘지 않는다.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icon, required this.color, this.badgeCount});

  final IconData icon;
  final Color color;
  final ValueListenable<int>? badgeCount;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 24, color: color);
    final count = badgeCount;
    if (count == null) return iconWidget;

    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (context, value, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          child!,
          if (value > 0)
            Positioned(top: -5, right: -9, child: _NavBadge(count: value)),
        ],
      ),
      child: iconWidget,
    );
  }
}

/// 미열람 건수 배지. 레일이 104px뿐이라 세 자리부터는 `99+`로 줄인다.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      container: true,
      // 스크린 리더가 숫자만 따로 읽지 않도록 자식 의미 정보를 대체한다.
      excludeSemantics: true,
      label: '읽지 않은 알림 ${count > 99 ? '99개 이상' : '$count건'}',
      child: Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: DodamHome.coral,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DodamHome.surface, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: DodamHome.surface,
          ),
        ),
      ),
    );
  }
}
