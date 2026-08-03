import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/auth.dart';

/// 보호자 설정의 진입 화면.
///
/// 세부 설정은 각 담당 화면에서 API를 연결하고, 이 화면은 사용자 정보와
/// 설정 메뉴를 한곳에 모아 제공한다.
class SettingsMainScreen extends StatefulWidget {
  const SettingsMainScreen({
    required this.user,
    required this.onSignOut,
    super.key,
  });

  final AuthenticatedUser? user;
  final AuthSignOut onSignOut;

  @override
  State<SettingsMainScreen> createState() => _SettingsMainScreenState();
}

class _SettingsMainScreenState extends State<SettingsMainScreen> {
  bool _isSigningOut = false;

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '로그아웃할까요?',
      message: '다시 이용하려면 소셜 로그인이 필요해요.',
      confirmLabel: '로그아웃',
      isDanger: true,
      illustration: const Icon(
        Icons.logout_rounded,
        size: 48,
        color: AppColors.inkMuted,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSigningOut = true);
    try {
      await widget.onSignOut();
      if (mounted) AppRouter.goLogin(context);
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '로그아웃하지 못했어요. 잠시 후 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  void _showPending(String title) {
    showAppMessage(context, message: '$title 화면은 준비 중이에요.');
  }

  void _openProfile() =>
      AppNavigation.pushNamed(context, AppRoutes.settingsProfile);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: const AppTopBar(title: '설정'),
    body: SafeArea(
      child: _SettingsContent(
        user: widget.user,
        isSigningOut: _isSigningOut,
        onItemSelected: _showPending,
        onProfileSelected: _openProfile,
        onSignOut: _signOut,
      ),
    ),
  );
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.user,
    required this.isSigningOut,
    required this.onItemSelected,
    required this.onProfileSelected,
    required this.onSignOut,
  });

  final AuthenticatedUser? user;
  final bool isSigningOut;
  final ValueChanged<String> onItemSelected;
  final VoidCallback onProfileSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.wideContentMaxWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileCard(user: user, onTap: onProfileSelected),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final account = _SettingsGroup(
                  children: [
                    _SettingsTile(
                      icon: Icons.person_outline_rounded,
                      title: '내 정보 관리',
                      subtitle: '닉네임 · 이메일 · 프로필',
                      onTap: onProfileSelected,
                    ),
                    _SettingsTile(
                      icon: Icons.lock_outline_rounded,
                      title: '개인정보 관리',
                      subtitle: '연결 계정 · 데이터 관리',
                      onTap: () => onItemSelected('개인정보 관리'),
                    ),
                  ],
                );
                final preferences = _SettingsGroup(
                  children: [
                    _SettingsTile(
                      icon: Icons.fact_check_outlined,
                      title: '동의 관리',
                      subtitle: '동의 현황 · 변경 · 철회',
                      onTap: () => AppNavigation.pushNamed(
                        context,
                        AppRoutes.settingsConsents,
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.notifications_none_rounded,
                      title: '알림 설정',
                      subtitle: '분석 완료 · 서비스 · 커뮤니티 알림',
                      onTap: () => onItemSelected('알림 설정'),
                    ),
                    _SettingsTile(
                      icon: Icons.inventory_2_outlined,
                      title: '데이터 보관 기간',
                      subtitle: '보관 기간과 삭제 기준 확인',
                      onTap: () => onItemSelected('데이터 보관 기간'),
                    ),
                  ],
                );

                if (constraints.maxWidth < 820) {
                  return Column(
                    children: [
                      account,
                      const SizedBox(height: AppSpacing.lg),
                      preferences,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: account),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: preferences),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  key: const ValueKey('settings-terms-tile'),
                  icon: Icons.description_outlined,
                  title: '약관 및 정책',
                  subtitle: '서비스 이용약관 · 개인정보 처리방침',
                  onTap: () =>
                      AppNavigation.pushNamed(context, AppRoutes.settingsTerms),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _AccountActions(
              isSigningOut: isSigningOut,
              onSignOut: onSignOut,
              onWithdraw: () =>
                  AppNavigation.pushNamed(context, AppRoutes.settingsWithdraw),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.onTap});

  final AuthenticatedUser? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nickname = user?.nickname?.trim();
    final displayName = nickname == null || nickname.isEmpty
        ? '보호자님'
        : nickname;
    final provider = switch (user?.provider) {
      AuthProvider.kakao => '카카오',
      AuthProvider.google => '구글',
      AuthProvider.naver => '네이버',
      null => '소셜',
    };

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.leafSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  size: 34,
                  color: AppColors.leaf,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: AppTypography.titleLg),
                    const SizedBox(height: AppSpacing.xxs),
                    Text('$provider 계정 연결됨', style: AppTypography.bodySm),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<_SettingsTile> children;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: AppColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(height: 1, indent: 68, endIndent: AppSpacing.md),
        ],
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 76,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xxs,
    ),
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.leafSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: AppColors.leaf),
    ),
    title: Text(title, style: AppTypography.bodyStrong),
    subtitle: Text(subtitle, style: AppTypography.bodySm),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      color: AppColors.inkMuted,
    ),
    onTap: onTap,
  );
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.isSigningOut,
    required this.onSignOut,
    required this.onWithdraw,
  });

  final bool isSigningOut;
  final VoidCallback onSignOut;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: AppColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        ListTile(
          key: const ValueKey('settings-logout-action'),
          minTileHeight: 64,
          title: Text('로그아웃', style: AppTypography.bodyStrong),
          trailing: isSigningOut
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout_rounded, color: AppColors.inkMuted),
          onTap: isSigningOut ? null : onSignOut,
        ),
        const Divider(
          height: 1,
          indent: AppSpacing.md,
          endIndent: AppSpacing.md,
        ),
        ListTile(
          key: const ValueKey('settings-withdraw-action'),
          minTileHeight: 64,
          title: Text(
            '회원 탈퇴',
            style: AppTypography.bodyStrong.copyWith(color: AppColors.error),
          ),
          subtitle: const Text(
            '서비스 데이터 처리 안내 후 진행',
            style: AppTypography.bodySm,
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.error,
          ),
          onTap: onWithdraw,
        ),
      ],
    ),
  );
}
