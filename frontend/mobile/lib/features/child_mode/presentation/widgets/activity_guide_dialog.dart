import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// S15P11B209-463·464: 활동 카드 선택 뒤 보여주는 공통 안내 팝업.
///
/// 그림일기(463)뿐 아니라 향후 추가되는 활동(예: 462 HTP)도 제목·설명·아이콘만
/// 바꿔 이 컴포넌트를 그대로 재사용한다. "시작하기"가 실제 세션 생성까지
/// 맡아 로딩·실패·재시도를 팝업 안에서 처리하고, 성공한 결과만 호출부로
/// 돌려준다.
Future<T?> showActivityGuideDialog<T>({
  required BuildContext context,
  required String title,
  required String description,
  required IconData icon,
  required Color accentColor,
  required Future<T> Function() onStart,
  String startLabel = '시작하기',
  String cancelLabel = '취소',
}) => showDialog<T>(
  context: context,
  builder: (dialogContext) => ActivityGuideDialog<T>(
    title: title,
    description: description,
    icon: icon,
    accentColor: accentColor,
    onStart: onStart,
    startLabel: startLabel,
    cancelLabel: cancelLabel,
  ),
);

enum _ActivityGuideStatus { idle, loading, error }

class ActivityGuideDialog<T> extends StatefulWidget {
  const ActivityGuideDialog({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.onStart,
    this.startLabel = '시작하기',
    this.cancelLabel = '취소',
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final Future<T> Function() onStart;
  final String startLabel;
  final String cancelLabel;

  @override
  State<ActivityGuideDialog<T>> createState() => _ActivityGuideDialogState<T>();
}

class _ActivityGuideDialogState<T> extends State<ActivityGuideDialog<T>> {
  _ActivityGuideStatus _status = _ActivityGuideStatus.idle;

  Future<void> _handleStart() async {
    if (_status == _ActivityGuideStatus.loading) return;
    setState(() => _status = _ActivityGuideStatus.loading);
    try {
      final result = await widget.onStart();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on Object {
      if (!mounted) return;
      setState(() => _status = _ActivityGuideStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _status == _ActivityGuideStatus.loading;
    final isError = _status == _ActivityGuideStatus.error;

    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      contentPadding: const EdgeInsets.all(AppSpacing.lg),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 52, color: widget.accentColor),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: AppTypography.titleLg,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.description,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.inkMuted),
            ),
            if (isError) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                label: '활동을 시작하지 못했어요. 다시 시도해 주세요.',
                child: ExcludeSemantics(
                  child: Container(
                    key: const ValueKey('activity-guide-error'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: AppIconSize.lg,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            '활동을 시작하지 못했어요. 다시 시도해 주세요.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    key: const ValueKey('activity-guide-cancel'),
                    label: widget.cancelLabel,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    key: const ValueKey('activity-guide-start'),
                    label: isError ? '다시 시도' : widget.startLabel,
                    variant: AppButtonVariant.child,
                    isLoading: isLoading,
                    onPressed: isLoading ? null : _handleStart,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
