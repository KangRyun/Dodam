import 'package:flutter/material.dart';

import '../../../../app/state/guardian_child_controller.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_dtos.dart';

typedef ChildProfileSelected =
    void Function(BuildContext context, ChildSummaryDto child);

class ProfileSelectionScreen extends StatelessWidget {
  const ProfileSelectionScreen({
    required this.controller,
    required this.onGuardianSelected,
    required this.onChildSelected,
    super.key,
  });

  final GuardianChildController controller;
  final ValueChanged<BuildContext> onGuardianSelected;
  final ChildProfileSelected onChildSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                children: [
                  const Text(
                    '누가 도담을 이용하나요?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    '이용할 프로필을 선택해 주세요',
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _ProfileGrid(
                    controller: controller,
                    onGuardianSelected: () => onGuardianSelected(context),
                    onChildSelected: (child) => onChildSelected(context, child),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProfileGrid extends StatelessWidget {
  const _ProfileGrid({
    required this.controller,
    required this.onGuardianSelected,
    required this.onChildSelected,
  });

  final GuardianChildController controller;
  final VoidCallback onGuardianSelected;
  final ValueChanged<ChildSummaryDto> onChildSelected;

  @override
  Widget build(BuildContext context) {
    final profiles = <Widget>[
      _ProfileCard(
        key: const ValueKey('guardian-profile'),
        label: '보호자',
        description: '기록과 리포트 확인',
        backgroundColor: AppColors.leafSoft,
        icon: Icons.family_restroom_rounded,
        iconColor: AppColors.leaf,
        onTap: onGuardianSelected,
      ),
      if (controller.status == ChildListStatus.success)
        for (final child in controller.children)
          _ProfileCard(
            key: ValueKey('child-profile-${child.childId}'),
            label: child.nickname,
            description: '${child.age}세 · 그림 활동',
            backgroundColor: AppColors.tangerineSoft,
            icon: Icons.face_rounded,
            iconColor: AppColors.tangerine,
            imageUrl: child.profileImageUrl,
            onTap: () => onChildSelected(child),
          ),
    ];

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.xl,
          children: profiles,
        ),
        if (controller.status == ChildListStatus.loading ||
            controller.status == ChildListStatus.idle) ...[
          const SizedBox(height: AppSpacing.xl),
          const AppLoadingView(message: '아이 프로필을 불러오고 있어요'),
        ],
        if (controller.status == ChildListStatus.error) ...[
          const SizedBox(height: AppSpacing.xl),
          AppRetryView(
            title: '아이 프로필을 불러오지 못했어요',
            message: '보호자 프로필은 바로 이용할 수 있어요.',
            onRetry: controller.loadChildren,
          ),
        ],
        if (controller.status == ChildListStatus.empty) ...[
          const SizedBox(height: AppSpacing.xl),
          const Text(
            '등록된 아이 프로필이 없어요',
            style: TextStyle(color: AppColors.inkMuted, fontSize: 16),
          ),
        ],
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.label,
    required this.description,
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.imageUrl,
    super.key,
  });

  final String label;
  final String description;
  final Color backgroundColor;
  final IconData icon;
  final Color iconColor;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label 프로필 선택',
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Container(
                width: 128,
                height: 128,
                color: backgroundColor,
                child: imageUrl == null
                    ? Icon(icon, size: 64, color: iconColor)
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(icon, size: 64, color: iconColor),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExpertProfileEntryScreen extends StatelessWidget {
  const ExpertProfileEntryScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: Center(
        child: AppEmptyView(
          title: '전문가 프로필',
          message: '전문가 계정으로 접속했어요.\n전문가 기능 화면이 연결될 예정이에요.',
        ),
      ),
    ),
  );
}
