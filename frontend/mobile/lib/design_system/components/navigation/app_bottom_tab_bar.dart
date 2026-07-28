import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_typography.dart';

/// 하단 탭 하나의 표시 정보.
class AppBottomTabItem {
  const AppBottomTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 보호자 모드 하단 탭 바.
///
/// 탭 전환 자체는 하지 않는다. 무엇이 선택됐는지 보여주고 탭을 알릴 뿐이라,
/// 화면 구조(중첩 Navigator·상태 유지)와 분리해 디자인 시스템에 둔다.
class AppBottomTabBar extends StatelessWidget {
  const AppBottomTabBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AppBottomTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.outline)),
    ),
    child: NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.leafSoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => AppTypography.label.copyWith(
          color: states.contains(WidgetState.selected)
              ? AppColors.leaf
              : AppColors.inkMuted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
      destinations: [
        for (final item in items)
          NavigationDestination(
            icon: Icon(item.icon, color: AppColors.inkMuted),
            selectedIcon: Icon(item.selectedIcon, color: AppColors.leaf),
            label: item.label,
            tooltip: item.label,
          ),
      ],
    ),
  );
}
