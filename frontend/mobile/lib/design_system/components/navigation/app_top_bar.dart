import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    required this.title,
    this.onBack,
    this.actions = const [],
    this.centerTitle = false,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool centerTitle;

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
    title: Text(
      title,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    actions: actions,
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, color: AppColors.surfaceSoft),
    ),
  );
}
