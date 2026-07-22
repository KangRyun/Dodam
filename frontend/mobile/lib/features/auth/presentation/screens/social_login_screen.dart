import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/enums/auth_provider.dart';
import '../../domain/failures/auth_failure.dart';

typedef SocialSignInCallback = Future<void> Function(AuthProvider provider);

class SocialLoginScreen extends StatefulWidget {
  const SocialLoginScreen({
    required this.onSignIn,
    this.onExpertGuideTap,
    this.onTermsTap,
    this.onPrivacyPolicyTap,
    super.key,
  });

  final SocialSignInCallback onSignIn;
  final VoidCallback? onExpertGuideTap;
  final VoidCallback? onTermsTap;
  final VoidCallback? onPrivacyPolicyTap;

  @override
  State<SocialLoginScreen> createState() => _SocialLoginScreenState();
}

class _SocialLoginScreenState extends State<SocialLoginScreen> {
  AuthProvider? _activeProvider;
  AuthProvider? _lastProvider;
  AuthFailure? _failure;

  bool get _isSigningIn => _activeProvider != null;

  Future<void> _signIn(AuthProvider provider) async {
    if (_isSigningIn) return;

    setState(() {
      _activeProvider = provider;
      _lastProvider = provider;
      _failure = null;
    });
    try {
      await widget.onSignIn(provider);
    } on AuthFailure catch (failure) {
      if (!mounted) return;

      if (failure.type != AuthFailureType.cancelled) {
        setState(() => _failure = failure);
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _failure = AuthFailure(
          type: AuthFailureType.unknown,
          message: '예상하지 못한 로그인 오류가 발생했어요.',
          cause: error,
        ),
      );
    } finally {
      if (mounted) setState(() => _activeProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 700;
          final horizontalPadding = isTablet ? AppSpacing.xxl : AppSpacing.lg;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - (AppSpacing.lg * 2)).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: EdgeInsets.all(isTablet ? AppSpacing.xl : 0),
                  decoration: isTablet
                      ? BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.outline),
                        )
                      : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: AppSpacing.xxl),
                      _SocialButtons(
                        activeProvider: _activeProvider,
                        enabled: !_isSigningIn,
                        onPressed: _signIn,
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _activeProvider != null
                            ? _LoginProgress(provider: _activeProvider!)
                            : _failure != null
                            ? _LoginFailurePanel(
                                failure: _failure!,
                                onRetry: _lastProvider == null
                                    ? null
                                    : () => _signIn(_lastProvider!),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ExpertGuideLink(onTap: widget.onExpertGuideTap),
                      const SizedBox(height: AppSpacing.xl),
                      _PolicyNotice(
                        onTermsTap: widget.onTermsTap,
                        onPrivacyPolicyTap: widget.onPrivacyPolicyTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _LoginProgress extends StatelessWidget {
  const _LoginProgress({required this.provider});

  final AuthProvider provider;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('login-progress'),
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Text(
      '${_providerLabel(provider)} 계정으로 연결하고 있어요…',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColors.inkMuted,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _LoginFailurePanel extends StatelessWidget {
  const _LoginFailurePanel({required this.failure, this.onRetry});

  final AuthFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('login-failure'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: AppSpacing.md),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.errorSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '로그인을 완료하지 못했어요',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _failureMessage(failure.type),
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (failure.canRetry && onRetry != null) ...[
                const SizedBox(height: AppSpacing.xs),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('다시 시도'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, AppSizes.minTouchTarget),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

String _providerLabel(AuthProvider provider) => switch (provider) {
  AuthProvider.kakao => '카카오',
  AuthProvider.google => '구글',
  AuthProvider.naver => '네이버',
};

String _failureMessage(AuthFailureType type) => switch (type) {
  AuthFailureType.network => '인터넷 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.',
  AuthFailureType.serverRejected => '잠시 로그인 서비스를 이용하기 어려워요. 잠시 후 다시 시도해 주세요.',
  AuthFailureType.providerRejected ||
  AuthFailureType.invalidCredential ||
  AuthFailureType.tokenExpired => '로그인 정보를 확인하지 못했어요. 다시 로그인해 주세요.',
  AuthFailureType.accountSuspended ||
  AuthFailureType.accountWithdrawn => '이 계정으로는 로그인할 수 없어요. 고객센터에 문의해 주세요.',
  AuthFailureType.cancelled => '로그인이 취소됐어요.',
  AuthFailureType.unknown => '예상하지 못한 문제가 발생했어요. 다시 시도해 주세요.',
};

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      _BrandMark(),
      SizedBox(height: AppSpacing.lg),
      Text(
        '그림과 대화로\n아이의 마음을 만나봐요',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          height: 1.32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
      SizedBox(height: AppSpacing.sm),
      Text(
        '아이가 편안하게 마음을 표현하도록\n도담이가 곁에서 함께할게요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkMuted, fontSize: 16, height: 1.5),
      ),
    ],
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '도담 로고',
    child: Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.leafSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Text('🖍️', style: TextStyle(fontSize: 44)),
    ),
  );
}

class _SocialButtons extends StatelessWidget {
  const _SocialButtons({
    required this.activeProvider,
    required this.enabled,
    required this.onPressed,
  });

  final AuthProvider? activeProvider;
  final bool enabled;
  final ValueChanged<AuthProvider> onPressed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SocialLoginButton(
        provider: SocialLoginProvider.kakao,
        isLoading: activeProvider == AuthProvider.kakao,
        onPressed: enabled ? () => onPressed(AuthProvider.kakao) : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      SocialLoginButton(
        provider: SocialLoginProvider.google,
        isLoading: activeProvider == AuthProvider.google,
        onPressed: enabled ? () => onPressed(AuthProvider.google) : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      SocialLoginButton(
        provider: SocialLoginProvider.naver,
        isLoading: activeProvider == AuthProvider.naver,
        onPressed: enabled ? () => onPressed(AuthProvider.naver) : null,
      ),
    ],
  );
}

class _ExpertGuideLink extends StatelessWidget {
  const _ExpertGuideLink({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.school_rounded, size: 18),
    label: const Text('상담사·치료사이신가요? 전문가 이용 안내'),
    style: TextButton.styleFrom(
      foregroundColor: AppColors.inkMuted,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class _PolicyNotice extends StatelessWidget {
  const _PolicyNotice({this.onTermsTap, this.onPrivacyPolicyTap});

  final VoidCallback? onTermsTap;
  final VoidCallback? onPrivacyPolicyTap;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text(
        '계속하면 ',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
      _PolicyButton(label: '이용약관', onPressed: onTermsTap),
      const Text(
        ' 및 ',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
      _PolicyButton(label: '개인정보 처리방침', onPressed: onPrivacyPolicyTap),
      const Text(
        '에 동의합니다.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
    ],
  );
}

class _PolicyButton extends StatelessWidget {
  const _PolicyButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, AppSizes.minTouchTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      foregroundColor: AppColors.ink,
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
      ),
    ),
    child: Text(label),
  );
}
