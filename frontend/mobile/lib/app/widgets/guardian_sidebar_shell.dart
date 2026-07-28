import 'package:flutter/material.dart';

import '../../features/guardian/presentation/widgets/guardian_home_theme.dart';

/// 사이드바 셸의 목적지 하나. [builder]는 처음 방문할 때 한 번만 만든다.
class GuardianNavItem {
  const GuardianNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final WidgetBuilder builder;
}

/// 태블릿 보호자 모드의 좌측 사이드바 셸(시안 1:1).
///
/// 흰 레일(104px) — 로고 + 세로 nav + 맨 아래 "프로필 전환". 본문은
/// [IndexedStack]으로 전환(탭 상태 보존). 배경은 따뜻한 크림(warm).
class GuardianSidebarShell extends StatefulWidget {
  const GuardianSidebarShell({
    required this.destinations,
    required this.onSwitchProfile,
    super.key,
  });

  final List<GuardianNavItem> destinations;
  final void Function(BuildContext context) onSwitchProfile;

  @override
  State<GuardianSidebarShell> createState() => _GuardianSidebarShellState();
}

class _GuardianSidebarShellState extends State<GuardianSidebarShell> {
  int _index = 0;
  final _visited = <int>{0};

  void _select(int index) {
    if (_index == index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

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
                Icon(resolvedIcon, size: 24, color: fg),
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
