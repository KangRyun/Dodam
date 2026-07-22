import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_dtos.dart';

class GuardianHomeScreen extends StatelessWidget {
  const GuardianHomeScreen({required this.controller, super.key});

  final GuardianChildController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: const AppTopBar(title: '보호자 홈'),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _buildBody(context),
      ),
    ),
  );

  Widget _buildBody(BuildContext context) => switch (controller.status) {
    ChildListStatus.idle || ChildListStatus.loading => const AppLoadingView(
      key: ValueKey('child-list-loading'),
      message: '아이 정보를 불러오고 있어요',
    ),
    ChildListStatus.error => AppRetryView(
      key: const ValueKey('child-list-error'),
      title: '아이 정보를 불러오지 못했어요',
      message: '잠시 후 다시 시도해 주세요.',
      onRetry: controller.loadChildren,
    ),
    ChildListStatus.empty => const AppEmptyView(
      key: ValueKey('child-list-empty'),
      title: '등록된 아이가 없어요',
      message: '아이 프로필을 등록하면 그림 활동을 시작할 수 있어요.',
    ),
    ChildListStatus.success => _GuardianHomeContent(controller: controller),
  };
}

class _GuardianHomeContent extends StatelessWidget {
  const _GuardianHomeContent({required this.controller});
  final GuardianChildController controller;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('child-list-success'),
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.wideContentMaxWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '보호자님, 오늘도 아이와 함께해요',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '활동할 아이를 선택하고 편안한 그림 시간을 시작해 주세요.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final selection = _ChildSelectionCard(controller: controller);
                final overview = _GuardianOverview(
                  selectedChild: controller.selectedChild,
                );
                if (constraints.maxWidth < 820) {
                  return Column(
                    children: [
                      selection,
                      const SizedBox(height: AppSpacing.lg),
                      overview,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: selection),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 4, child: overview),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey('start-child-mode'),
              label: '그림 활동 시작하기',
              leading: const Icon(Icons.palette_outlined),
              onPressed: controller.selectedChild == null
                  ? null
                  : () => Navigator.of(context).pushNamed(
                      AppRoutes.childModeHome(
                        controller.selectedChild!.childId.toString(),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const ValueKey('activity-history-entry'),
              label: '활동 이력 보기',
              leading: const Icon(Icons.history_rounded),
              variant: AppButtonVariant.secondary,
              onPressed: controller.selectedChild == null
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.activityHistory),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: '아동 선택 화면에서 보기',
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.childSelect),
            ),
          ],
        ),
      ),
    ),
  );
}

class ChildSelectScreen extends StatelessWidget {
  const ChildSelectScreen({required this.controller, super.key});
  final GuardianChildController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '활동 대상 아동 선택',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => switch (controller.status) {
          ChildListStatus.idle || ChildListStatus.loading =>
            const AppLoadingView(message: '아이 정보를 불러오고 있어요'),
          ChildListStatus.error => AppRetryView(
            onRetry: controller.loadChildren,
          ),
          ChildListStatus.empty => const AppEmptyView(
            title: '선택할 아이가 없어요',
            message: '먼저 아이 프로필을 등록해 주세요.',
          ),
          ChildListStatus.success => _ChildSelectContent(
            controller: controller,
          ),
        },
      ),
    ),
  );
}

class _ChildSelectContent extends StatelessWidget {
  const _ChildSelectContent({required this.controller});
  final GuardianChildController controller;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '누가 그림 활동을 시작하나요?',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '선택한 아이 정보는 보호자 세션 안에서만 유지돼요.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ChildSelectionCard(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: '선택한 아이로 시작',
              onPressed: controller.selectedChild == null
                  ? null
                  : () => Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.childModeHome(
                        controller.selectedChild!.childId.toString(),
                      ),
                      (route) => route.settings.name == AppRoutes.guardianHome,
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChildSelectionCard extends StatelessWidget {
  const _ChildSelectionCard({required this.controller});
  final GuardianChildController controller;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '등록된 아이',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final child in controller.children) ...[
          AppChoiceCard(
            key: ValueKey('child-${child.childId}'),
            label: child.nickname,
            description:
                '${child.age}세 · 활동 ${child.recentActivity.totalActivityCount}회',
            isSelected: controller.selectedChildId == child.childId,
            onTap: () => controller.selectChild(child),
            leading: _ChildAvatar(child: child),
          ),
          if (child != controller.children.last)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _GuardianOverview extends StatelessWidget {
  const _GuardianOverview({required this.selectedChild});
  final ChildSummaryDto? selectedChild;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.leafSoft,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '선택된 아이 요약',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (selectedChild == null)
          const Text(
            '왼쪽에서 활동할 아이를 선택해 주세요.',
            style: TextStyle(color: AppColors.inkMuted),
          )
        else ...[
          Row(
            children: [
              _ChildAvatar(child: selectedChild!),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  selectedChild!.nickname,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '최근 활동 ${selectedChild!.recentActivity.totalActivityCount}회',
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            selectedChild!.recentActivity.lastActivityAt == null
                ? '아직 기록된 활동이 없어요.'
                : '최근 활동: ${selectedChild!.recentActivity.lastActivityAt}',
            style: const TextStyle(color: AppColors.inkMuted),
          ),
        ],
        const Divider(height: AppSpacing.xl),
        const _OverviewPlaceholder(
          icon: Icons.insights_outlined,
          label: '월간 활동 요약',
          caption: '활동 통계 연결 예정',
        ),
        const SizedBox(height: AppSpacing.sm),
        const _OverviewPlaceholder(
          icon: Icons.description_outlined,
          label: '관찰 리포트',
          caption: '리포트 화면 연결 예정',
        ),
      ],
    ),
  );
}

class _OverviewPlaceholder extends StatelessWidget {
  const _OverviewPlaceholder({
    required this.icon,
    required this.label,
    required this.caption,
  });
  final IconData icon;
  final String label, caption;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppColors.leaf),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              caption,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ChildAvatar extends StatelessWidget {
  const _ChildAvatar({required this.child});
  final ChildSummaryDto child;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: Container(
      width: AppSizes.childAvatar,
      height: AppSizes.childAvatar,
      color: AppColors.tangerineSoft,
      child: child.profileImageUrl == null
          ? const Icon(Icons.face_rounded, color: AppColors.tangerine, size: 38)
          : Image.network(
              child.profileImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.face_rounded,
                color: AppColors.tangerine,
                size: 38,
              ),
            ),
    ),
  );
}

class GuardianConfirmScreen extends StatelessWidget {
  const GuardianConfirmScreen({required this.activityId, super.key});
  final String activityId;
  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '보호자 확인',
    description: '아동 활동이 끝난 뒤 보호자가 결과를 확인하는 화면이에요.',
    primaryLabel: '활동 상세 보기',
    onPrimary: () => Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.activityDetail(activityId)),
  );
}
