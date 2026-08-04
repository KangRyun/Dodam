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

  void _openProfile() =>
      AppNavigation.pushNamed(context, AppRoutes.settingsProfile);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ForgePalette.canvas,
    appBar: const AppTopBar(title: '설정'),
    body: SafeArea(
      child: _SettingsContent(
        user: widget.user,
        isSigningOut: _isSigningOut,
        onProfileSelected: _openProfile,
        onSignOut: _signOut,
      ),
    ),
  );
}

abstract final class _ForgePalette {
  static const canvas = Color(0xFFFFF9EF);
  static const surface = Color(0xFFFFFDF7);
  static const sage = Color(0xFFDDEAD5);
  static const sageSoft = Color(0xFFEEF5E9);
  static const forest = Color(0xFF315B49);
  static const parchment = Color(0xFFF7EAC8);
  static const parchmentSoft = Color(0xFFFFF8E8);
  static const outline = Color(0xFFE7D9B8);
  static const brass = Color(0xFFC89B3C);
  static const walnut = Color(0xFF795035);
  static const ember = Color(0xFFDF8448);
  static const ink = Color(0xFF2F3531);
  static const inkMuted = Color(0xFF717970);
  static const danger = Color(0xFFC45E4D);
  static const dangerSoft = Color(0xFFF9EBE7);
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.user,
    required this.isSigningOut,
    required this.onProfileSelected,
    required this.onSignOut,
  });

  final AuthenticatedUser? user;
  final bool isSigningOut;
  final VoidCallback onProfileSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewportConstraints) {
      final horizontalPadding = switch (viewportConstraints.maxWidth) {
        < 480 => AppSpacing.md,
        < 900 => AppSpacing.lg,
        _ => AppSpacing.xl,
      };

      return SingleChildScrollView(
        key: const ValueKey('settings-scroll-view'),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.lg,
          horizontalPadding,
          AppSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.wideContentMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, contentConstraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ForgeBanner(
                    user: user,
                    availableWidth: contentConstraints.maxWidth,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SettingsGroups(
                    availableWidth: contentConstraints.maxWidth,
                    isSigningOut: isSigningOut,
                    onProfileSelected: onProfileSelected,
                    onSignOut: onSignOut,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ForgeBanner extends StatelessWidget {
  const _ForgeBanner({required this.user, required this.availableWidth});

  final AuthenticatedUser? user;
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    final isCompact = availableWidth < 640;
    final frameSize = switch (availableWidth) {
      >= 960 => 168.0,
      >= 640 => 148.0,
      _ => 116.0,
    };
    final nickname = user?.nickname?.trim();
    final displayName = nickname == null || nickname.isEmpty
        ? '보호자님'
        : nickname;
    final provider = switch (user?.provider) {
      AuthProvider.kakao => '카카오',
      AuthProvider.google => '구글',
      AuthProvider.naver => '네이버',
      null => null,
    };
    final accountLabel = provider == null
        ? '$displayName의 계정 정보를 확인해 주세요'
        : '$displayName · $provider 계정 연결됨';

    final character = _BlacksmithFrame(size: frameSize);
    final copy = Column(
      crossAxisAlignment: isCompact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '설정 화면 콘셉트',
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: _ForgePalette.sageSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: _ForgePalette.outline),
            ),
            child: Text(
              '도담이 대장간',
              style: AppTypography.label.copyWith(
                color: _ForgePalette.forest,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          header: true,
          child: Text(
            '설정을 차근차근 정리해요',
            textAlign: isCompact ? TextAlign.center : TextAlign.start,
            style: AppTypography.titleLg.copyWith(color: _ForgePalette.forest),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '계정과 앱 사용 환경을 보호자님에게 맞게 관리할 수 있어요.',
          textAlign: isCompact ? TextAlign.center : TextAlign.start,
          style: AppTypography.body.copyWith(color: _ForgePalette.inkMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _ForgePalette.parchmentSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: _ForgePalette.outline),
          ),
          child: Text(
            accountLabel,
            textAlign: isCompact ? TextAlign.center : TextAlign.start,
            style: AppTypography.bodySm.copyWith(
              color: _ForgePalette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '설정 안내',
      child: Container(
        key: const ValueKey('settings-forge-banner'),
        decoration: BoxDecoration(
          color: _ForgePalette.sage,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: _ForgePalette.outline),
          boxShadow: [
            BoxShadow(
              color: _ForgePalette.walnut.withValues(alpha: 0.09),
              offset: Offset(0, 5),
              blurRadius: 12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg - 1),
          child: Stack(
            children: [
              const Positioned.fill(child: _ForgeBannerDecoration()),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? AppSpacing.lg : AppSpacing.xl,
                  vertical: isCompact ? AppSpacing.lg : AppSpacing.xl,
                ),
                child: isCompact
                    ? Column(
                        children: [
                          character,
                          const SizedBox(height: AppSpacing.lg),
                          copy,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          character,
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(child: copy),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForgeBannerDecoration extends StatelessWidget {
  const _ForgeBannerDecoration();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Stack(
        children: [
          Positioned(
            right: -28,
            bottom: -44,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                color: Color(0x18EEF5E9),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(left: 14, top: 14, child: _BrassRivet()),
          const Positioned(right: 14, top: 14, child: _BrassRivet()),
          Positioned(
            right: 28,
            bottom: 18,
            child: Container(
              width: 104,
              height: 2,
              color: _ForgePalette.brass.withValues(alpha: 0.32),
            ),
          ),
          Positioned(
            right: 48,
            bottom: 26,
            child: Container(
              width: 64,
              height: 2,
              color: _ForgePalette.ember.withValues(alpha: 0.18),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BrassRivet extends StatelessWidget {
  const _BrassRivet();

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: _ForgePalette.brass.withValues(alpha: 0.5),
      shape: BoxShape.circle,
      border: Border.all(color: _ForgePalette.parchmentSoft, width: 1),
    ),
  );
}

class _BlacksmithFrame extends StatelessWidget {
  const _BlacksmithFrame({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('settings-blacksmith-frame'),
    width: size,
    height: size,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: _ForgePalette.parchment,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: _ForgePalette.brass, width: 2),
      boxShadow: [
        BoxShadow(
          color: _ForgePalette.walnut.withValues(alpha: 0.25),
          offset: Offset(0, 6),
          blurRadius: 0,
        ),
      ],
    ),
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: _ForgePalette.parchmentSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg - 6),
        border: Border.all(color: _ForgePalette.outline),
      ),
      clipBehavior: Clip.hardEdge,
      child: Semantics(
        image: true,
        label: '설정을 정리하는 대장장이 도담이',
        child: ExcludeSemantics(
          child: Transform.scale(
            scale: 1.22,
            alignment: const Alignment(0, -0.02),
            child: Image.asset(
              'assets/characters/dodami_blacksmith_profile.png',
              key: const ValueKey('settings-blacksmith-character'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SettingsGroups extends StatelessWidget {
  const _SettingsGroups({
    required this.availableWidth,
    required this.isSigningOut,
    required this.onProfileSelected,
    required this.onSignOut,
  });

  final double availableWidth;
  final bool isSigningOut;
  final VoidCallback onProfileSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final account = _SettingsSection(
      title: '계정과 프로필',
      icon: Icons.person_outline_rounded,
      children: [
        _SettingsTile(
          key: const ValueKey('settings-profile-tile'),
          icon: Icons.badge_outlined,
          title: '보호자 정보',
          subtitle: '닉네임과 연결 계정을 확인하고 관리해요',
          onTap: onProfileSelected,
        ),
        _SettingsTile(
          key: const ValueKey('settings-consents-tile'),
          icon: Icons.fact_check_outlined,
          title: '동의 관리',
          subtitle: '동의 현황을 확인하고 변경하거나 철회해요',
          onTap: () =>
              AppNavigation.pushNamed(context, AppRoutes.settingsConsents),
        ),
      ],
    );
    final preferences = _SettingsSection(
      title: '앱 사용 설정',
      icon: Icons.tune_rounded,
      children: [
        _SettingsTile(
          key: const ValueKey('settings-notifications-tile'),
          icon: Icons.notifications_none_rounded,
          title: '알림 설정',
          subtitle: '분석 완료 · 서비스 · 커뮤니티 알림을 관리해요',
          onTap: () =>
              AppNavigation.pushNamed(context, AppRoutes.settingsNotifications),
        ),
        _SettingsTile(
          key: const ValueKey('settings-data-retention-tile'),
          icon: Icons.inventory_2_outlined,
          title: '데이터 보관 기간',
          subtitle: '보관 기간과 안내 시점을 설정해요',
          onTap: () =>
              AppNavigation.pushNamed(context, AppRoutes.settingsDataRetention),
        ),
      ],
    );
    final service = _SettingsSection(
      title: '서비스 정보',
      icon: Icons.menu_book_outlined,
      children: [
        _SettingsTile(
          key: const ValueKey('settings-terms-tile'),
          icon: Icons.description_outlined,
          title: '약관 및 정책',
          subtitle: '서비스 이용약관과 개인정보처리방침을 확인해요',
          onTap: () =>
              AppNavigation.pushNamed(context, AppRoutes.settingsTerms),
        ),
      ],
    );
    final accountActions = _SettingsSection(
      title: '계정 관리',
      icon: Icons.shield_outlined,
      children: [
        _SettingsTile(
          key: const ValueKey('settings-logout-action'),
          icon: Icons.logout_rounded,
          title: isSigningOut ? '로그아웃하는 중' : '로그아웃',
          subtitle: '현재 계정에서 안전하게 나가요',
          onTap: isSigningOut ? null : onSignOut,
          trailing: isSigningOut
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        _SettingsTile(
          key: const ValueKey('settings-withdraw-action'),
          icon: Icons.person_remove_outlined,
          title: '회원 탈퇴',
          subtitle: '서비스 데이터 처리 안내를 확인한 뒤 진행해요',
          isDanger: true,
          onTap: () =>
              AppNavigation.pushNamed(context, AppRoutes.settingsWithdraw),
        ),
      ],
    );

    if (availableWidth < 760) {
      return Column(
        children: [
          account,
          const SizedBox(height: AppSpacing.lg),
          preferences,
          const SizedBox(height: AppSpacing.lg),
          service,
          const SizedBox(height: AppSpacing.lg),
          accountActions,
        ],
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: account),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: preferences),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: service),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: accountActions),
          ],
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<_SettingsTile> children;

  @override
  Widget build(BuildContext context) => Material(
    color: _ForgePalette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: _ForgePalette.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _ForgePalette.sageSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: _ForgePalette.outline),
                  ),
                  child: Icon(
                    icon,
                    size: AppIconSize.md,
                    color: _ForgePalette.forest,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.titleMd.copyWith(
                      color: _ForgePalette.forest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: _ForgePalette.outline),
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(
              height: 1,
              indent: 76,
              endIndent: AppSpacing.md,
              color: _ForgePalette.outline,
            ),
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
    this.trailing,
    this.isDanger = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool isDanger;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '$title, $subtitle',
    child: ExcludeSemantics(
      child: ListTile(
        minTileHeight: 76,
        minVerticalPadding: AppSpacing.sm,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDanger ? _ForgePalette.dangerSoft : _ForgePalette.sageSoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isDanger
                  ? _ForgePalette.danger.withValues(alpha: 0.28)
                  : _ForgePalette.outline,
            ),
          ),
          child: Icon(
            icon,
            color: isDanger ? _ForgePalette.danger : _ForgePalette.forest,
          ),
        ),
        title: Text(
          title,
          style: AppTypography.bodyStrong.copyWith(
            color: isDanger ? _ForgePalette.danger : _ForgePalette.ink,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(
            subtitle,
            style: AppTypography.bodySm.copyWith(color: _ForgePalette.inkMuted),
          ),
        ),
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: isDanger ? _ForgePalette.danger : _ForgePalette.brass,
            ),
        onTap: onTap,
      ),
    ),
  );
}
