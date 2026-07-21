import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

enum AppMessageType { info, success, warning, error }

void showAppMessage(
  BuildContext context, {
  required String message,
  AppMessageType type = AppMessageType.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final visual = _visualFor(type);
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: visual.background,
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        content: Row(
          children: [
            Icon(visual.icon, color: visual.foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: visual.foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: visual.foreground,
                onPressed: onAction,
              ),
      ),
    );
}

class _MessageVisual {
  const _MessageVisual(this.background, this.foreground, this.icon);

  final Color background;
  final Color foreground;
  final IconData icon;
}

_MessageVisual _visualFor(AppMessageType type) => switch (type) {
  AppMessageType.info => const _MessageVisual(
    AppColors.lavenderSoft,
    AppColors.ink,
    Icons.auto_awesome_rounded,
  ),
  AppMessageType.success => const _MessageVisual(
    AppColors.successSoft,
    AppColors.success,
    Icons.check_circle_rounded,
  ),
  AppMessageType.warning => const _MessageVisual(
    AppColors.warningSoft,
    AppColors.warning,
    Icons.wb_sunny_rounded,
  ),
  AppMessageType.error => const _MessageVisual(
    AppColors.errorSoft,
    AppColors.error,
    Icons.error_rounded,
  ),
};
