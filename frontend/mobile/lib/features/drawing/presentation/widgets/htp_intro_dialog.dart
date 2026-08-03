import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 부모 홈에서 집·나무·사람(HTP) 그림 활동을 시작하기 전에 보여주는 소개 팝업
/// (S15P11B209-462).
///
/// 무엇을 그리는 활동인지 짧게 소개하고, "시작하기"를 눌러야 실제 활동 흐름으로
/// 넘어간다. 활동이 심리 진단이 아니라 참고 자료임을 함께 알린다(앱 전반의 면책
/// 톤과 일치). 세션 생성은 이후 화면이 맡고, 이 팝업은 진행 의사만 돌려준다.
///
/// 반환값: 시작하면 `true`, 취소하거나 바깥을 눌러 닫으면 `false`/`null`.
Future<bool?> showHtpIntroDialog(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (_) => const HtpIntroDialog(),
);

class HtpIntroDialog extends StatelessWidget {
  const HtpIntroDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
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
              decoration: const BoxDecoration(
                color: AppColors.tangerineSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.home_rounded,
                size: 50,
                color: AppColors.tangerine,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            '집·나무·사람 그림 활동',
            textAlign: TextAlign.center,
            style: AppTypography.titleLg,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '아이가 집, 나무, 사람을 순서대로 그리며 마음을 표현하는 그림 활동이에요.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          const Row(
            children: [
              Expanded(
                child: _HtpElement(
                  icon: Icons.home_rounded,
                  label: '집',
                  color: AppColors.tangerine,
                ),
              ),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _HtpElement(
                  icon: Icons.park_rounded,
                  label: '나무',
                  color: AppColors.leaf,
                ),
              ),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _HtpElement(
                  icon: Icons.person_rounded,
                  label: '사람',
                  color: AppColors.lavender,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: AppIconSize.lg,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '전문적인 심리 진단이 아니라, 아이의 마음을 이해하는 참고 자료로 '
                    '활용돼요.',
                    style: AppTypography.bodySm,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('htp-intro-cancel'),
                  label: '취소',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  key: const ValueKey('htp-intro-start'),
                  label: '시작하기',
                  variant: AppButtonVariant.child,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 소개 팝업 안에서 무엇을 그리는지 보여주는 요소 칩(집·나무·사람).
class _HtpElement extends StatelessWidget {
  const _HtpElement({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: AppSpacing.xxs),
        Text(label, style: AppTypography.bodyStrong),
      ],
    ),
  );
}
