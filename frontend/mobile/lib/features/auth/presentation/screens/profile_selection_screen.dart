import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../child_mode/domain/dodam_costume.dart';

typedef ChildProfileSelected =
    void Function(BuildContext context, ChildSummaryDto child);

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({
    required this.controller,
    required this.onGuardianSelected,
    required this.onChildSelected,
    this.imageFetcher,
    this.onAddChild,
    this.onEditProfiles,
    this.onEditChild,
    this.onSettings,
    this.headerAction,
    super.key,
  });

  final GuardianChildController controller;
  final ValueChanged<BuildContext> onGuardianSelected;
  final ChildProfileSelected onChildSelected;
  final ImageByteFetcher? imageFetcher;
  final ValueChanged<BuildContext>? onAddChild;
  final ValueChanged<BuildContext>? onEditProfiles;
  final ChildProfileSelected? onEditChild;
  final ValueChanged<BuildContext>? onSettings;

  /// 로그아웃처럼 자체 확인·실행 계약을 가진 기존 action을 설정 sheet에 표시한다.
  final Widget? headerAction;

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  bool _isEditingProfiles = false;
  bool _guardianNavigationStarted = false;
  int? _navigatingChildId;
  bool _settingsSheetOpen = false;

  bool get _isChildListReady =>
      widget.controller.status == ChildListStatus.success ||
      widget.controller.status == ChildListStatus.empty;

  void _selectGuardian() {
    if (!_isChildListReady ||
        _guardianNavigationStarted ||
        _navigatingChildId != null) {
      return;
    }
    _guardianNavigationStarted = true;
    widget.onGuardianSelected(context);
  }

  void _selectChild(ChildSummaryDto child) {
    if (!_isChildListReady ||
        _guardianNavigationStarted ||
        _navigatingChildId != null) {
      return;
    }
    if (_isEditingProfiles && widget.onEditChild != null) {
      widget.onEditChild!(context, child);
      return;
    }
    _navigatingChildId = child.childId;
    widget.onChildSelected(context, child);
  }

  void _toggleProfileEditing() {
    if (widget.onEditChild != null) {
      setState(() => _isEditingProfiles = !_isEditingProfiles);
      return;
    }
    widget.onEditProfiles?.call(context);
  }

  Future<void> _showSettings() async {
    if (_settingsSheetOpen) return;
    _settingsSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _ProfileSettingsSheet(
        isEditingProfiles: _isEditingProfiles,
        canEditProfiles:
            widget.onEditChild != null || widget.onEditProfiles != null,
        onEditProfiles: () {
          Navigator.of(sheetContext).pop();
          _toggleProfileEditing();
        },
        onSettings: widget.onSettings == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                widget.onSettings!(context);
              },
        logoutAction: widget.headerAction,
      ),
    );
    _settingsSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ProfileColors.cream,
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, viewport) {
            final horizontalPadding = viewport.maxWidth < 480
                ? AppSpacing.md
                : AppSpacing.xl;
            return SingleChildScrollView(
              key: const ValueKey('profile-selection-scroll'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.sm,
                horizontalPadding,
                AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileTopBar(onSettings: _showSettings),
                      const SizedBox(height: AppSpacing.lg),
                      _ProfileHeader(
                        guardianEnabled:
                            _isChildListReady &&
                            !_guardianNavigationStarted &&
                            _navigatingChildId == null,
                        onGuardianSelected: _selectGuardian,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _ChildProfileSection(
                        controller: widget.controller,
                        imageFetcher: widget.imageFetcher,
                        isEditing: _isEditingProfiles,
                        navigationEnabled:
                            !_guardianNavigationStarted &&
                            _navigatingChildId == null,
                        onChildSelected: _selectChild,
                        onAddChild: widget.onAddChild == null
                            ? null
                            : () => widget.onAddChild!(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const ExcludeSemantics(child: _DodamWordmark()),
      const Spacer(),
      Semantics(
        key: const ValueKey('profile-selection-settings'),
        sortKey: const OrdinalSortKey(4),
        button: true,
        label: '프로필 선택 설정',
        onTap: onSettings,
        excludeSemantics: true,
        child: IconButton(
          tooltip: '설정',
          constraints: const BoxConstraints.tightFor(width: 52, height: 52),
          style: IconButton.styleFrom(
            backgroundColor: _ProfileColors.settingsBackground,
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: _ProfileColors.settingsBorder),
          ),
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined, size: 27),
        ),
      ),
    ],
  );
}

class _DodamWordmark extends StatelessWidget {
  const _DodamWordmark();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: _ProfileColors.logo,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 18),
      ),
      SizedBox(width: AppSpacing.sm),
      Text(
        '도담',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.guardianEnabled,
    required this.onGuardianSelected,
  });

  final bool guardianEnabled;
  final VoidCallback onGuardianSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final useRow = constraints.maxWidth >= 720;
      final title = Column(
        crossAxisAlignment: useRow
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(
              key: const ValueKey('profile-selection-title'),
              useRow ? '누가 도담이와 함께할까요?' : '누가 도담이와\n함께할까요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: useRow ? 34 : 30,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            key: const ValueKey('profile-selection-description'),
            '활동을 시작할 아동 프로필을 선택해 주세요.',
            textAlign: useRow ? TextAlign.start : TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 17,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
      final guardian = _GuardianModeButton(
        enabled: guardianEnabled,
        expanded: !useRow,
        onSelected: onGuardianSelected,
      );
      if (!useRow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: AppSpacing.lg),
            guardian,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: AppSpacing.xl),
          guardian,
        ],
      );
    },
  );
}

class _GuardianModeButton extends StatelessWidget {
  const _GuardianModeButton({
    required this.enabled,
    required this.expanded,
    required this.onSelected,
  });

  final bool enabled;
  final bool expanded;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: expanded ? double.infinity : 246,
    child: Semantics(
      key: const ValueKey('guardian-profile'),
      sortKey: const OrdinalSortKey(1),
      button: true,
      enabled: enabled,
      label: '보호자 모드로 이동',
      onTap: enabled ? onSelected : null,
      excludeSemantics: true,
      child: Material(
        color: _ProfileColors.guardianBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: const BorderSide(color: _ProfileColors.green),
        ),
        child: InkWell(
          key: const ValueKey('guardian-mode-action'),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled ? onSelected : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 44,
                    child: Image(
                      key: ValueKey('guardian-dodami-image'),
                      image: AssetImage(_ProfileAssets.guardian),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      '보호자 모드로',
                      maxLines: 2,
                      style: TextStyle(
                        color: _ProfileColors.greenDark,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: _ProfileColors.greenDark,
                    size: 23,
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

class _ChildProfileSection extends StatelessWidget {
  const _ChildProfileSection({
    required this.controller,
    required this.imageFetcher,
    required this.isEditing,
    required this.navigationEnabled,
    required this.onChildSelected,
    this.onAddChild,
  });

  final GuardianChildController controller;
  final ImageByteFetcher? imageFetcher;
  final bool isEditing;
  final bool navigationEnabled;
  final ValueChanged<ChildSummaryDto> onChildSelected;
  final VoidCallback? onAddChild;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('child-profile-section'),
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: _ProfileColors.childBackground,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: _ProfileColors.orange.withValues(alpha: 0.62)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isEditing) ...[
          Semantics(
            liveRegion: true,
            child: const Text(
              '수정하거나 삭제할 아이를 선택해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ProfileColors.orangeDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        LayoutBuilder(
          builder: (context, constraints) =>
              _buildProfiles(context, constraints.maxWidth),
        ),
      ],
    ),
  );

  Widget _buildProfiles(BuildContext context, double availableWidth) =>
      switch (controller.status) {
        ChildListStatus.idle || ChildListStatus.loading => const SizedBox(
          height: 220,
          child: AppLoadingView(message: '아이 프로필을 불러오고 있어요'),
        ),
        ChildListStatus.error => SizedBox(
          height: 240,
          child: AppFailureView(
            title: '아이 프로필을 불러오지 못했어요',
            failure: controller.listError,
            onRetry: controller.loadChildren,
          ),
        ),
        ChildListStatus.empty => Column(
          children: [
            const Text(
              '등록된 아동 프로필이 아직 없어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildProfileGrid(context, availableWidth),
          ],
        ),
        ChildListStatus.success => _buildProfileGrid(context, availableWidth),
      };

  Widget _buildProfileGrid(BuildContext context, double availableWidth) {
    const spacing = AppSpacing.md;
    final itemCount = controller.children.length + 1;
    final maxColumns = switch (availableWidth) {
      >= 1040 => 5,
      >= 820 => 4,
      >= 580 => 3,
      >= 300 => 2,
      _ => 1,
    };
    final columns = math.min(itemCount, maxColumns);
    final idealCardWidth = availableWidth < 480 ? 164.0 : 184.0;
    final widthForColumns =
        (availableWidth - (spacing * (columns - 1))) / columns;
    final cardWidth = math.min(idealCardWidth, widthForColumns);
    final gridWidth = (cardWidth * columns) + (spacing * (columns - 1));
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 214 + ((textScale - 1).clamp(0, 1) * 42).toDouble();
    return Center(
      child: SizedBox(
        width: gridWidth,
        child: GridView.builder(
          key: const ValueKey('child-profile-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: cardHeight,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemBuilder: (context, index) {
            if (index == controller.children.length) {
              return _AddChildCard(onTap: onAddChild);
            }
            final child = controller.children[index];
            return _ChildProfileCard(
              key: ValueKey('child-profile-${child.childId}'),
              child: child,
              imageFetcher: imageFetcher,
              isSelected:
                  controller.hasExplicitChildSelection &&
                  controller.selectedChildId == child.childId,
              enabled: navigationEnabled,
              sortOrder: 2 + (index / 100),
              onTap: () => onChildSelected(child),
            );
          },
        ),
      ),
    );
  }
}

class _ChildProfileCard extends StatelessWidget {
  const _ChildProfileCard({
    required this.child,
    required this.imageFetcher,
    required this.isSelected,
    required this.enabled,
    required this.sortOrder,
    required this.onTap,
    super.key,
  });

  final ChildSummaryDto child;
  final ImageByteFetcher? imageFetcher;
  final bool isSelected;
  final bool enabled;
  final double sortOrder;
  final VoidCallback onTap;

  String get _label {
    final nickname = child.nickname.trim();
    if (child.age <= 0) return nickname;
    return '$nickname · ${child.age}세';
  }

  Widget _fallback(BuildContext context) => Image.asset(
    DodamCostume.fromCode(child.preferredCharacter).asset,
    fit: BoxFit.cover,
    semanticLabel: '${child.nickname} 도담이',
  );

  @override
  Widget build(BuildContext context) => Semantics(
    sortKey: OrdinalSortKey(sortOrder),
    button: true,
    enabled: enabled,
    selected: isSelected,
    label: '$_label 아이 프로필 선택${isSelected ? ', 선택됨' : ''}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isSelected ? _ProfileColors.orange : AppColors.outline,
              width: isSelected ? 3 : 1,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final avatarSize = (constraints.maxWidth * 0.62).clamp(
                72.0,
                100.0,
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipOval(
                        child: ColoredBox(
                          color: _ProfileColors.avatarBackground,
                          child: SizedBox.square(
                            dimension: avatarSize,
                            child:
                                child.profileImageUrl != null &&
                                    imageFetcher != null
                                ? AuthenticatedImage(
                                    key: ValueKey(
                                      'child-authenticated-image-${child.childId}',
                                    ),
                                    url: child.profileImageUrl,
                                    fetcher: imageFetcher!,
                                    fit: BoxFit.cover,
                                    semanticLabel: '${child.nickname} 프로필 사진',
                                    placeholderBuilder: _fallback,
                                  )
                                : _fallback(context),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            key: ValueKey(
                              'child-profile-selected-${child.childId}',
                            ),
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: _ProfileColors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    child.nickname.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (child.age > 0) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${child.age}세',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              );
            },
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
    sortKey: const OrdinalSortKey(3),
    button: true,
    enabled: onTap != null,
    label: '아이 프로필 추가',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('add-child-profile'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: _ProfileColors.orange, width: 2),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                color: _ProfileColors.orangeDark,
                size: 44,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                '추가',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ProfileColors.orangeDark,
                  fontSize: 15,
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

class _ProfileSettingsSheet extends StatelessWidget {
  const _ProfileSettingsSheet({
    required this.isEditingProfiles,
    required this.canEditProfiles,
    required this.onEditProfiles,
    this.onSettings,
    this.logoutAction,
  });

  final bool isEditingProfiles;
  final bool canEditProfiles;
  final VoidCallback onEditProfiles;
  final VoidCallback? onSettings;
  final Widget? logoutAction;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '프로필 선택 설정',
    child: Padding(
      key: const ValueKey('profile-selection-settings-sheet'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('설정', style: AppTypography.titleLg),
          const SizedBox(height: AppSpacing.md),
          if (canEditProfiles)
            ListTile(
              key: const ValueKey('edit-child-profiles'),
              minTileHeight: 56,
              leading: const Icon(Icons.edit_outlined),
              title: Text(isEditingProfiles ? '편집 완료' : '프로필 편집'),
              onTap: onEditProfiles,
            ),
          if (onSettings != null)
            ListTile(
              key: const ValueKey('open-guardian-settings'),
              minTileHeight: 56,
              leading: const Icon(Icons.settings_outlined),
              title: const Text('전체 설정'),
              onTap: onSettings,
            ),
          if (logoutAction != null)
            Row(
              key: const ValueKey('profile-selection-logout-row'),
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.logout_rounded),
                const SizedBox(width: 32),
                const Expanded(child: Text('로그아웃')),
                logoutAction!,
              ],
            ),
        ],
      ),
    ),
  );
}

abstract final class _ProfileAssets {
  static const guardian = 'assets/images/role_selection/guardian_dodami.png';
}

abstract final class _ProfileColors {
  static const cream = Color(0xFFFFFAEE);
  static const logo = Color(0xFFE8A13A);
  static const green = Color(0xFF7DA97B);
  static const greenDark = Color(0xFF457248);
  static const guardianBackground = Color(0xFFF4F8EF);
  static const orange = Color(0xFFE99A46);
  static const orangeDark = Color(0xFFC9682C);
  static const childBackground = Color(0xFFFFF6E6);
  static const avatarBackground = Color(0xFFFFFCF5);
  static const settingsBackground = Color(0xFFFFF8E9);
  static const settingsBorder = Color(0xFFE2CBA6);
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
