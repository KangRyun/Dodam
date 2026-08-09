import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

class AppPlaceholderScaffold extends StatelessWidget {
  const AppPlaceholderScaffold({
    required this.title,
    required this.description,
    this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.childFriendly = false,
    this.canPop = true,
    super.key,
  });

  final String title;
  final String description;
  final Widget? body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool childFriendly;
  final bool canPop;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canPop,
    child: Scaffold(
      backgroundColor: childFriendly ? AppColors.childCanvas : AppColors.canvas,
      appBar: AppTopBar(
        title: title,
        onBack: canPop ? () => Navigator.of(context).maybePop() : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          childFriendly
                              ? Icons.palette_outlined
                              : Icons.dashboard_outlined,
                          size: AppSizes.stateIcon,
                          color: childFriendly
                              ? AppColors.tangerine
                              : AppColors.leaf,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppColors.inkMuted,
                                height: childFriendly ? 1.5 : 1.45,
                                fontWeight: childFriendly
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (body case final body?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    body,
                  ],
                  if (primaryLabel case final primaryLabel?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: primaryLabel,
                      onPressed: onPrimary,
                      variant: childFriendly
                          ? AppButtonVariant.child
                          : AppButtonVariant.primary,
                    ),
                  ],
                  if (secondaryLabel case final secondaryLabel?) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: secondaryLabel,
                      onPressed: onSecondary,
                      variant: AppButtonVariant.secondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
