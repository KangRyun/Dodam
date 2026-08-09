import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../../tokens/app_typography.dart';

enum AppButtonVariant { primary, child, secondary, quiet, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final Widget? leading;
  final Widget? trailing;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(variant);
    final enabled = onPressed != null && !isLoading;
    final height = variant == AppButtonVariant.child
        ? AppSizes.childButtonHeight
        : AppSizes.buttonHeight;

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: isLoading ? '$label 처리 중' : label,
      child: SizedBox(
        height: height,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabled;
              }
              if (states.contains(WidgetState.pressed)) {
                return colors.pressed;
              }
              return colors.background;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.onDisabled;
              }
              return colors.foreground;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isLoading
                ? SizedBox.square(
                    key: const ValueKey('loading'),
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.foreground,
                    ),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (leading case final leading?) ...[
                        IconTheme(
                          data: const IconThemeData(size: 22),
                          child: leading,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.button,
                        ),
                      ),
                      if (trailing case final trailing?) ...[
                        const SizedBox(width: AppSpacing.xs),
                        IconTheme(
                          data: const IconThemeData(size: 22),
                          child: trailing,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _ButtonColors {
  const _ButtonColors({
    required this.background,
    required this.pressed,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color pressed;
  final Color foreground;
  final Color border;
}

_ButtonColors _colorsFor(AppButtonVariant variant) => switch (variant) {
  AppButtonVariant.primary => const _ButtonColors(
    background: AppColors.leaf,
    pressed: AppColors.leafPressed,
    foreground: Colors.white,
    border: Colors.transparent,
  ),
  AppButtonVariant.child => const _ButtonColors(
    background: AppColors.tangerine,
    pressed: AppColors.tangerinePressed,
    foreground: Colors.white,
    border: Colors.transparent,
  ),
  AppButtonVariant.secondary => const _ButtonColors(
    background: AppColors.surface,
    pressed: AppColors.leafSoft,
    foreground: AppColors.ink,
    border: AppColors.outline,
  ),
  AppButtonVariant.quiet => const _ButtonColors(
    background: AppColors.surfaceSoft,
    pressed: AppColors.outline,
    foreground: AppColors.ink,
    border: Colors.transparent,
  ),
  AppButtonVariant.danger => const _ButtonColors(
    background: AppColors.errorSoft,
    pressed: Color(0xFFF4D4D1),
    foreground: AppColors.error,
    border: Colors.transparent,
  ),
};
