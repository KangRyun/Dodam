import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../buttons/app_button.dart';

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    this.message = '잠시만 기다려 주세요',
    this.childFriendly = false,
    super.key,
  });

  final String message;
  final bool childFriendly;

  @override
  Widget build(BuildContext context) => _AppStateLayout(
    semanticsLabel: message,
    liveRegion: true,
    visual: SizedBox.square(
      dimension: AppSizes.loadingIndicator,
      child: CircularProgressIndicator(
        color: childFriendly ? AppColors.tangerine : AppColors.leaf,
      ),
    ),
    message: message,
    childFriendly: childFriendly,
  );
}

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    this.title = '문제가 발생했어요',
    this.message = '잠시 후 다시 시도해 주세요.',
    this.onRetry,
    this.retryLabel = '다시 시도',
    this.childFriendly = false,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool childFriendly;

  @override
  Widget build(BuildContext context) => _AppStateLayout(
    semanticsLabel: '$title. $message',
    visual: const _StateIcon(
      icon: Icons.error_outline_rounded,
      foreground: AppColors.error,
      background: AppColors.errorSoft,
    ),
    title: title,
    message: message,
    childFriendly: childFriendly,
    action: onRetry == null
        ? null
        : _AppStateAction(
            label: retryLabel,
            onPressed: onRetry!,
            childFriendly: childFriendly,
            icon: Icons.refresh_rounded,
          ),
  );
}

class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    this.title = '아직 내용이 없어요',
    this.message,
    this.actionLabel,
    this.onAction,
    this.childFriendly = false,
    super.key,
  });

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool childFriendly;

  @override
  Widget build(BuildContext context) {
    final accent = childFriendly ? AppColors.tangerine : AppColors.leaf;
    final background = childFriendly
        ? AppColors.tangerineSoft
        : AppColors.leafSoft;
    final showAction = actionLabel != null && onAction != null;

    return _AppStateLayout(
      semanticsLabel: [title, if (message != null) message].join('. '),
      visual: _StateIcon(
        icon: childFriendly ? Icons.auto_awesome_rounded : Icons.inbox_outlined,
        foreground: accent,
        background: background,
      ),
      title: title,
      message: message,
      childFriendly: childFriendly,
      action: showAction
          ? _AppStateAction(
              label: actionLabel!,
              onPressed: onAction!,
              childFriendly: childFriendly,
              icon: Icons.add_rounded,
            )
          : null,
    );
  }
}

class AppRetryView extends StatelessWidget {
  const AppRetryView({
    required this.onRetry,
    this.title = '연결이 원활하지 않아요',
    this.message = '인터넷 연결을 확인하고 다시 시도해 주세요.',
    this.retryLabel = '다시 시도',
    this.childFriendly = false,
    super.key,
  });

  final VoidCallback onRetry;
  final String title;
  final String message;
  final String retryLabel;
  final bool childFriendly;

  @override
  Widget build(BuildContext context) => _AppStateLayout(
    semanticsLabel: '$title. $message',
    visual: _StateIcon(
      icon: Icons.wifi_off_rounded,
      foreground: childFriendly ? AppColors.tangerine : AppColors.warning,
      background: childFriendly
          ? AppColors.tangerineSoft
          : AppColors.warningSoft,
    ),
    title: title,
    message: message,
    childFriendly: childFriendly,
    action: _AppStateAction(
      label: retryLabel,
      onPressed: onRetry,
      childFriendly: childFriendly,
      icon: Icons.refresh_rounded,
    ),
  );
}

class _AppStateLayout extends StatelessWidget {
  const _AppStateLayout({
    required this.semanticsLabel,
    required this.visual,
    required this.message,
    required this.childFriendly,
    this.title,
    this.action,
    this.liveRegion = false,
  });

  final String semanticsLabel;
  final Widget visual;
  final String? title;
  final String? message;
  final Widget? action;
  final bool childFriendly;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      liveRegion: liveRegion,
      label: semanticsLabel,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.contentMaxWidth,
            ),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  visual,
                  if (title case final title?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (message case final message?) ...[
                    SizedBox(
                      height: title == null ? AppSpacing.md : AppSpacing.xs,
                    ),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge?.copyWith(
                        color: AppColors.inkMuted,
                        height: childFriendly ? 1.5 : 1.45,
                        fontWeight: childFriendly
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                  if (action case final action?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    width: AppSizes.stateIcon,
    height: AppSizes.stateIcon,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Icon(icon, color: foreground, size: AppSizes.iconButton),
  );
}

class _AppStateAction extends StatelessWidget {
  const _AppStateAction({
    required this.label,
    required this.onPressed,
    required this.childFriendly,
    required this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final bool childFriendly;
  final IconData icon;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onPressed: onPressed,
    variant: childFriendly
        ? AppButtonVariant.child
        : AppButtonVariant.secondary,
    leading: Icon(icon),
    expand: false,
  );
}
