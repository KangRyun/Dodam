import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../../tokens/app_typography.dart';

const Color dodamDialogScrim = Color(0x80536B5B);

abstract final class DodamDialogAssets {
  static const String completeThumbsUp =
      'assets/images/dialogs/dialog_complete_thumbsup.png';
  static const String completeThinking =
      'assets/images/dialogs/dialog_complete_thinking.png';
  static const String conversationStopCrying =
      'assets/images/dialogs/dialog_conversation_stop_crying.png';
  static const String diary = 'assets/images/dialogs/dialog_diary_pastel.png';
  static const String guardianHandhold =
      'assets/images/dialogs/dialog_guardian_handhold.png';
  static const String htp = 'assets/images/dialogs/dialog_htp_pastel.png';
  static const String warning =
      'assets/images/dialogs/dialog_warning_pastel.png';
}

enum DodamDialogButtonKind { primary, secondary, danger }

/// 도담의 아동 화면과 같은 따뜻한 종이 질감의 공용 다이얼로그 카드.
///
/// 제목·본문·액션의 의미 순서를 유지하고, 본문은 큰 글자에서도 스크롤할 수
/// 있다. 액션은 실제 할당 폭과 text scale을 기준으로 가로/세로를 전환한다.
class DodamDialog extends StatelessWidget {
  const DodamDialog({
    required this.title,
    required this.actions,
    this.illustration,
    this.message,
    this.extra,
    this.scrollable = false,
    super.key,
  });

  final Widget? illustration;
  final String title;
  final String? message;
  final Widget? extra;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final windowSize = MediaQuery.sizeOf(context);
    final horizontalInset = windowSize.width < 360
        ? AppSpacing.sm
        : AppSpacing.lg;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: AppSpacing.md,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: windowSize.height * 0.88,
        ),
        child: DecoratedBox(
          key: const ValueKey('dodam-dialog-card'),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: const Color(0xFFD8C9B5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x245A4939),
                blurRadius: 14,
                offset: Offset(4, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('dodam-dialog-scroll-view'),
                    physics: scrollable ? const ClampingScrollPhysics() : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (illustration case final illustration?) ...[
                          ExcludeSemantics(
                            child: IgnorePointer(child: illustration),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTypography.titleLg,
                          ),
                        ),
                        if (message case final message?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                        if (extra case final extra?) ...[
                          const SizedBox(height: AppSpacing.md),
                          extra,
                        ],
                      ],
                    ),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _DodamDialogActions(actions: actions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DodamDialogButton extends StatelessWidget {
  const DodamDialogButton({
    required this.label,
    required this.onPressed,
    this.kind = DodamDialogButtonKind.primary,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final DodamDialogButtonKind kind;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = _buttonColors(kind);
    final enabled = onPressed != null && !loading;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: enabled ? colors.border : AppColors.outline),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label 처리 중' : label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSizes.minTouchTarget,
          minHeight: AppSizes.minTouchTarget,
        ),
        child: Material(
          color: enabled ? colors.background : AppColors.disabled,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            customBorder: shape,
            overlayColor: WidgetStatePropertyAll(colors.pressed),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: loading ? 0 : 1,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.button.copyWith(
                        color: enabled
                            ? colors.foreground
                            : AppColors.onDisabled,
                      ),
                    ),
                  ),
                  if (loading)
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.foreground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '확인',
  String cancelLabel = '취소',
  bool isDanger = false,
  Widget? illustration,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: dodamDialogScrim,
  builder: (context) => DodamDialog(
    illustration:
        illustration ??
        Image.asset(
          DodamDialogAssets.warning,
          key: const ValueKey('dodam-dialog-warning-illustration'),
          width: 184,
          height: 138,
          fit: BoxFit.contain,
        ),
    title: title,
    message: message,
    scrollable: true,
    actions: [
      DodamDialogButton(
        label: cancelLabel,
        kind: DodamDialogButtonKind.secondary,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      DodamDialogButton(
        label: confirmLabel,
        kind: isDanger
            ? DodamDialogButtonKind.danger
            : DodamDialogButtonKind.primary,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  ),
);

class _DodamDialogActions extends StatelessWidget {
  const _DodamDialogActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final useColumn = constraints.maxWidth < 320 || textScale >= 1.6;

      if (useColumn) {
        return Column(
          key: const ValueKey('dodam-dialog-actions-column'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              SizedBox(width: double.infinity, child: actions[index]),
              if (index != actions.length - 1)
                const SizedBox(height: AppSpacing.xs),
            ],
          ],
        );
      }

      return Row(
        key: const ValueKey('dodam-dialog-actions-row'),
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: actions[index]),
            if (index != actions.length - 1)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      );
    },
  );
}

class _DodamDialogButtonColors {
  const _DodamDialogButtonColors({
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

_DodamDialogButtonColors _buttonColors(DodamDialogButtonKind kind) =>
    switch (kind) {
      DodamDialogButtonKind.primary => const _DodamDialogButtonColors(
        background: Color(0xFFF1B179),
        pressed: Color(0xFFE29C60),
        foreground: Color(0xFF493225),
        border: Color(0xFFD99A64),
      ),
      DodamDialogButtonKind.secondary => const _DodamDialogButtonColors(
        background: Color(0xFFF7F1E7),
        pressed: Color(0xFFE4E9DC),
        foreground: AppColors.ink,
        border: Color(0xFFD8C9B5),
      ),
      DodamDialogButtonKind.danger => const _DodamDialogButtonColors(
        background: Color(0xFFE7A39A),
        pressed: Color(0xFFD88980),
        foreground: Color(0xFF552B27),
        border: Color(0xFFCF847A),
      ),
    };
