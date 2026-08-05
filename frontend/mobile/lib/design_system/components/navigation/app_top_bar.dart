import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    required this.title,
    this.onBack,
    this.actions = const [],
    this.centerTitle = false,
    this.titleLeading,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool centerTitle;

  /// 제목 앞에 붙는 장식 위젯. 주지 않으면 제목만 그린다(기존 동작).
  final Widget? titleLeading;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: centerTitle,
    toolbarHeight: preferredSize.height,
    leading: onBack == null
        ? null
        : Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: IconButton.filledTonal(
              tooltip: '뒤로 가기',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceSoft,
                foregroundColor: AppColors.ink,
                minimumSize: const Size.square(AppSizes.iconButton),
              ),
            ),
          ),
    title: titleLeading == null
        ? _title()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              titleLeading!,
              const SizedBox(width: AppSpacing.xs),
              // 좁은 폭에서 제목이 아이콘을 밀어내지 않게 남는 폭만 쓰게 한다.
              Flexible(child: _title()),
            ],
          ),
    actions: actions,
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, color: AppColors.surfaceSoft),
    ),
  );

  Widget _title() => Text(
    title,
    style: const TextStyle(
      color: AppColors.ink,
      fontSize: 21,
      fontWeight: FontWeight.w800,
    ),
  );
}
