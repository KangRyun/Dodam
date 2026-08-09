import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

class AppCheckboxTile extends StatelessWidget {
  const AppCheckboxTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.isRequired = false,
    super.key,
  });

  final String label;
  final String? description;
  final bool value;
  final bool isRequired;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (next) => onChanged!(next ?? false),
              activeColor: AppColors.leaf,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm / 2),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: label,
                      children: [
                        if (isRequired)
                          const TextSpan(
                            text: '  필수',
                            style: TextStyle(color: AppColors.tangerine),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (description case final description?) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AppChoiceCard extends StatelessWidget {
  const AppChoiceCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.description,
    this.leading,
    this.childFriendly = false,
    super.key,
  });

  final String label;
  final String? description;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool childFriendly;

  @override
  Widget build(BuildContext context) {
    final accent = childFriendly ? AppColors.tangerine : AppColors.leaf;
    final selectedSurface = childFriendly
        ? AppColors.tangerineSoft
        : AppColors.leafSoft;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? selectedSurface : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: isSelected ? accent : AppColors.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.buttonHeight),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  if (leading case final leading?) ...[
                    leading,
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (description case final description?) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            description,
                            style: const TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle_rounded, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
