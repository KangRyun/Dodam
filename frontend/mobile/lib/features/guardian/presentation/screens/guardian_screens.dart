import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../child_mode/domain/dodam_costume.dart';
import '../../../notification/application/notification_badge_controller.dart';
import '../../../notification/application/push_registration_status_controller.dart';
import '../../../notification/domain/repositories/notification_inbox_repository.dart';
import '../widgets/guardian_dashboard.dart';

class GuardianHomeScreen extends StatelessWidget {
  const GuardianHomeScreen({
    required this.controller,
    this.activityRepository,
    this.notificationInboxRepository,
    this.notificationBadgeController,
    this.pushRegistrationStatus,
    super.key,
  });

  final GuardianChildController controller;

  /// 마음 달력·최근 활동을 그리는 데 쓰는 활동 이력 레포.
  final ActivityRepository? activityRepository;

  /// 헤더 알림 버튼 팝업이 쓰는 알림함·배지·푸시 등록 상태.
  final NotificationInboxRepository? notificationInboxRepository;
  final NotificationBadgeController? notificationBadgeController;
  final PushRegistrationStatusController? pushRegistrationStatus;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _buildBody(context),
  );

  Widget _buildBody(BuildContext context) => switch (controller.status) {
    ChildListStatus.idle || ChildListStatus.loading => const AppLoadingView(
      key: ValueKey('child-list-loading'),
      message: '아이 정보를 불러오고 있어요',
    ),
    ChildListStatus.error => AppFailureView(
      key: const ValueKey('child-list-error'),
      title: '아이 정보를 불러오지 못했어요',
      failure: controller.listError,
      onRetry: controller.loadChildren,
    ),
    ChildListStatus.empty => AppEmptyView(
      key: const ValueKey('child-list-empty'),
      title: '등록된 아이가 없어요',
      message: '아이 프로필을 등록하면 그림 활동을 시작할 수 있어요.',
      actionLabel: '아이 등록하기',
      onAction: () => AppNavigation.pushNamed(context, AppRoutes.childRegister),
    ),
    ChildListStatus.success => GuardianDashboard(
      key: ValueKey('guardian-dashboard-${controller.selectedChildId}'),
      controller: controller,
      activityRepository: activityRepository,
      notificationInboxRepository: notificationInboxRepository,
      notificationBadgeController: notificationBadgeController,
      pushRegistrationStatus: pushRegistrationStatus,
    ),
  };
}

class ChildSelectScreen extends StatelessWidget {
  const ChildSelectScreen({
    required this.controller,
    this.imageFetcher,
    super.key,
  });
  final GuardianChildController controller;
  final ImageByteFetcher? imageFetcher;

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
          ChildListStatus.error => AppFailureView(
            title: '아이 정보를 불러오지 못했어요',
            failure: controller.listError,
            onRetry: controller.loadChildren,
          ),
          ChildListStatus.empty => const AppEmptyView(
            title: '선택할 아이가 없어요',
            message: '먼저 아이 프로필을 등록해 주세요.',
          ),
          ChildListStatus.success => _ChildSelectContent(
            controller: controller,
            imageFetcher: imageFetcher,
          ),
        },
      ),
    ),
  );
}

class _ChildSelectContent extends StatelessWidget {
  const _ChildSelectContent({required this.controller, this.imageFetcher});
  final GuardianChildController controller;
  final ImageByteFetcher? imageFetcher;

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
            _ChildSelectionCard(
              controller: controller,
              imageFetcher: imageFetcher,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: '선택한 아이로 시작',
              // 보호자 홈은 최상단에 그대로 두고 그 위에 아동 모드를 얹는다.
              // 아이가 활동을 마치면 뒤로가기 한 번으로 보호자 모드에 돌아온다.
              onPressed: controller.selectedChild == null
                  ? null
                  : () => AppNavigation.pushNamed(
                      context,
                      AppRoutes.childModeHome(
                        controller.selectedChild!.childId.toString(),
                      ),
                      rootNavigator: true,
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChildSelectionCard extends StatelessWidget {
  const _ChildSelectionCard({required this.controller, this.imageFetcher});
  final GuardianChildController controller;
  final ImageByteFetcher? imageFetcher;

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
            leading: _ChildAvatar(child: child, imageFetcher: imageFetcher),
          ),
          if (child != controller.children.last)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _ChildAvatar extends StatelessWidget {
  const _ChildAvatar({required this.child, this.imageFetcher});
  final ChildSummaryDto child;
  final ImageByteFetcher? imageFetcher;

  Widget _fallback(BuildContext context) => Image.asset(
    DodamCostume.fromCode(child.preferredCharacter).asset,
    fit: BoxFit.cover,
    semanticLabel: '${child.nickname} 도담이',
  );

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Container(
      width: AppSizes.childAvatar,
      height: AppSizes.childAvatar,
      color: AppColors.tangerineSoft,
      child: child.profileImageUrl != null && imageFetcher != null
          ? AuthenticatedImage(
              url: child.profileImageUrl,
              fetcher: imageFetcher!,
              fit: BoxFit.cover,
              semanticLabel: '${child.nickname} 프로필 사진',
              placeholderBuilder: _fallback,
            )
          : _fallback(context),
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
