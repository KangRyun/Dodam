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
    this.onAddChild,
    this.onEditProfiles,
    this.headerAction,
    super.key,
  });

  final GuardianChildController controller;
  final ValueChanged<BuildContext> onGuardianSelected;
  final ChildProfileSelected onChildSelected;
  final ValueChanged<BuildContext>? onAddChild;
  final ValueChanged<BuildContext>? onEditProfiles;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ProfileColors.cream,
    body: SafeArea(
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.xs,
                  AppSpacing.xxl,
                  AppSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    children: [
                      const _ProfileHeader(),
                      const SizedBox(height: AppSpacing.xl),
                      _GuardianSection(
                        onSelected: () => onGuardianSelected(context),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ChildrenSection(
                        controller: controller,
                        onChildSelected: (child) =>
                            onChildSelected(context, child),
                        onAddChild: onAddChild == null
                            ? null
                            : () => onAddChild!(context),
                        onEditProfiles: onEditProfiles == null
                            ? null
                            : () => onEditProfiles!(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (headerAction != null)
            Positioned(top: 0, right: 0, child: headerAction!),
        ],
      ),
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: double.infinity,
    child: Column(
      children: [
        Text(
          '누가 도담을 이용하나요?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          '이용할 프로필을 선택해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 18),
        ),
      ],
    ),
  );
}

class _GuardianSection extends StatelessWidget {
  const _GuardianSection({required this.onSelected});

  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '보호자 프로필 선택',
    child: InkWell(
      key: const ValueKey('guardian-profile'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onSelected,
      child: _SectionContainer(
        color: AppColors.surface,
        borderColor: _ProfileColors.green,
        child: const Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: _ProfileColors.greenSoft,
              child: Icon(
                Icons.family_restroom_rounded,
                size: 36,
                color: _ProfileColors.green,
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(
                    icon: Icons.person_outline_rounded,
                    label: '보호자 프로필',
                    color: _ProfileColors.green,
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    '보호자 홈에서 아이의 기록과 리포트를 확인해요',
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: _ProfileColors.green,
              size: 22,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChildrenSection extends StatelessWidget {
  const _ChildrenSection({
    required this.controller,
    required this.onChildSelected,
    this.onAddChild,
    this.onEditProfiles,
  });

  final GuardianChildController controller;
  final ValueChanged<ChildSummaryDto> onChildSelected;
  final VoidCallback? onAddChild;
  final VoidCallback? onEditProfiles;

  @override
  Widget build(BuildContext context) => _SectionContainer(
    color: _ProfileColors.childSection,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionTitle(
                icon: Icons.child_care_rounded,
                label: '아동 프로필',
                color: _ProfileColors.orange,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('edit-child-profiles'),
              onPressed: onEditProfiles,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('프로필 편집'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ProfileColors.orange,
                side: const BorderSide(color: _ProfileColors.orange),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 184, child: _buildProfiles()),
      ],
    ),
  );

  Widget _buildProfiles() => switch (controller.status) {
    ChildListStatus.idle || ChildListStatus.loading => const AppLoadingView(
      message: '아이 프로필을 불러오고 있어요',
    ),
    ChildListStatus.error => AppRetryView(
      title: '아이 프로필을 불러오지 못했어요',
      message: '잠시 후 다시 시도해 주세요.',
      onRetry: controller.loadChildren,
    ),
    ChildListStatus.empty => Row(
      children: [
        _AddChildCard(onTap: onAddChild),
        const SizedBox(width: AppSpacing.md),
        const Text(
          '아이 프로필을 등록하면\n그림 활동을 시작할 수 있어요.',
          style: TextStyle(color: AppColors.inkMuted, height: 1.5),
        ),
      ],
    ),
    ChildListStatus.success => ListView.separated(
      key: const ValueKey('child-profile-carousel'),
      scrollDirection: Axis.horizontal,
      itemCount: controller.children.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) {
        if (index == controller.children.length) {
          return _AddChildCard(onTap: onAddChild);
        }
        final child = controller.children[index];
        return _ChildProfileCard(
          key: ValueKey('child-profile-${child.childId}'),
          child: child,
          isSelected: controller.selectedChildId == child.childId,
          onTap: () => onChildSelected(child),
        );
      },
    ),
  };
}

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({
    required this.color,
    required this.child,
    this.borderColor = AppColors.outline,
  });

  final Color color;
  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(
        color: borderColor,
        width: borderColor == AppColors.outline ? 1 : 3,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F27313A),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(width: AppSpacing.sm),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 21,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _ChildProfileCard extends StatelessWidget {
  const _ChildProfileCard({
    required this.child,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final ChildSummaryDto child;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SelectableProfileCard(
    label: child.nickname,
    width: 164,
    borderColor: isSelected ? _ProfileColors.orange : AppColors.outline,
    onTap: onTap,
    avatar: CircleAvatar(
      radius: 44,
      backgroundColor: AppColors.surface,
      backgroundImage: child.profileImageUrl == null
          ? null
          : NetworkImage(child.profileImageUrl!),
      child: child.profileImageUrl == null
          ? const Icon(
              Icons.face_rounded,
              size: 48,
              color: _ProfileColors.orange,
            )
          : null,
    ),
  );
}

class _SelectableProfileCard extends StatefulWidget {
  const _SelectableProfileCard({
    required this.label,
    required this.width,
    required this.borderColor,
    required this.avatar,
    required this.onTap,
  });

  final String label;
  final double width;
  final Color borderColor;
  final Widget avatar;
  final VoidCallback onTap;

  @override
  State<_SelectableProfileCard> createState() => _SelectableProfileCardState();
}

class _SelectableProfileCardState extends State<_SelectableProfileCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${widget.label} 프로필 선택',
    child: FocusableActionDetector(
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: widget.width,
          height: 180,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: _isFocused ? _ProfileColors.orange : widget.borderColor,
              width: _isFocused || widget.borderColor != AppColors.outline
                  ? 3
                  : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.avatar,
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AddChildCard extends StatelessWidget {
  const _AddChildCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '아이 프로필 추가',
    child: InkWell(
      key: const ValueKey('add-child-profile'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        width: 164,
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: _ProfileColors.orange,
            style: BorderStyle.solid,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: _ProfileColors.orange,
              size: 42,
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              '아이 프로필 추가',
              style: TextStyle(
                color: _ProfileColors.orange,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

abstract final class _ProfileColors {
  static const cream = Color(0xFFFFFCF5);
  static const orange = Color(0xFFE88A45);
  static const green = Color(0xFF77A982);
  static const greenSoft = Color(0xFFE9F3EB);
  static const childSection = Color(0xFFF2D765);
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
