import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 부모 홈에서 집·나무·사람(HTP) 그림 활동을 시작하기 전에 보여주는 소개 팝업
/// (S15P11B209-462).
///
/// 반환값: 시작하면 `true`, 취소하거나 바깥을 눌러 닫으면 `false`/`null`.
Future<bool?> showHtpIntroDialog(BuildContext context) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: dodamDialogScrim,
  builder: (_) => const HtpIntroDialog(),
);

class HtpIntroDialog extends StatelessWidget {
  const HtpIntroDialog({super.key});

  @override
  Widget build(BuildContext context) => DodamDialog(
    scrollable: true,
    illustration: const _HtpPastelIllustration(),
    title: '집·나무·사람 그림 활동',
    message: '아이가 집, 나무, 사람을 순서대로 그리며 마음을 표현하는 그림 활동이에요.',
    extra: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
        SizedBox(height: AppSpacing.md),
        _HtpNotice(),
      ],
    ),
    actions: [
      DodamDialogButton(
        key: const ValueKey('htp-intro-cancel'),
        label: '취소',
        kind: DodamDialogButtonKind.secondary,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      DodamDialogButton(
        key: const ValueKey('htp-intro-start'),
        label: '시작하기',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}

class _HtpPastelIllustration extends StatelessWidget {
  const _HtpPastelIllustration();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 176),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: 1.5,
              child: Image.asset(
                DodamDialogAssets.htp,
                key: const ValueKey('htp-intro-pastel-illustration'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HtpNotice extends StatelessWidget {
  const _HtpNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F1E8),
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: const Color(0xFFD8C9B5)),
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
            '전문적인 심리 진단이 아니라, 아이의 마음을 이해하는 참고 자료로 활용돼요.',
            style: AppTypography.bodySm,
          ),
        ),
      ],
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
      color: const Color(0xFFFFFCF5),
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: const Color(0xFFD8C9B5)),
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
