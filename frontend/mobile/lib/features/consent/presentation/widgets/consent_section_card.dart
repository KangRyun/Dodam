import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 동의·약관 화면의 묶음 카드. 제목 아래에 내용을 세로로 쌓는다.
class ConsentSectionCard extends StatelessWidget {
  const ConsentSectionCard({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: AppColors.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.titleLg),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    ),
  );
}

/// 약관의 필수/선택 여부 배지. 서버가 정한 값을 표시만 한다.
class ConsentRequirementBadge extends StatelessWidget {
  const ConsentRequirementBadge({required this.required, super.key});

  final bool required;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = required
        ? ('필수', AppColors.ink, AppColors.surfaceSoft)
        : ('선택', AppColors.leaf, AppColors.leafSoft);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
