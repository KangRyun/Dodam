import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/auth_landing_resolver.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/new_user_onboarding_input.dart';
import '../../domain/enums/auth_provider.dart';
import '../../domain/enums/user_role.dart';
import '../models/auth_state.dart';
import 'new_user_onboarding_flow_screen.dart';
import 'social_login_screen.dart';

typedef AuthProviderSignIn = Future<AuthState> Function(AuthProvider provider);
typedef AuthOnboardingComplete =
    Future<AuthSession> Function(NewUserOnboardingInput input);
typedef AuthGuardianNavigation = void Function(BuildContext context);

class AuthenticationFlowScreen extends StatefulWidget {
  const AuthenticationFlowScreen({
    required this.onSignIn,
    required this.onCompleteOnboarding,
    required this.onProfileSelectionRequired,
    required this.onExpertAuthenticated,
    super.key,
  });

  final AuthProviderSignIn onSignIn;
  final AuthOnboardingComplete onCompleteOnboarding;
  final AuthGuardianNavigation onProfileSelectionRequired;
  final AuthGuardianNavigation onExpertAuthenticated;

  @override
  State<AuthenticationFlowScreen> createState() =>
      _AuthenticationFlowScreenState();
}

class _AuthenticationFlowScreenState extends State<AuthenticationFlowScreen> {
  AuthSession? _onboardingSession;
  bool _showsUnsupportedRole = false;

  // 소셜 로그인 결과에 따른 다음 화면 결정
  Future<void> _signIn(AuthProvider provider) async {
    final state = await widget.onSignIn(provider);
    final failure = state.failure;
    if (failure != null) throw failure;

    final session = state.session;
    if (session == null) return;

    if (session.requiresOnboarding) {
      setState(() => _onboardingSession = session);
      return;
    }

    _moveToRoleDestination(session.user.role);
  }

  // 온보딩 입력 역할에 따른 다음 화면 결정
  Future<void> _completeOnboarding(NewUserOnboardingInput input) async {
    final session = await widget.onCompleteOnboarding(input);
    _moveToRoleDestination(session.user.role);
  }

  void _moveToRoleDestination(UserRole? role) {
    switch (AuthLandingResolver.resolve(role)) {
      case AuthLandingDestination.profileSelection:
        widget.onProfileSelectionRequired(context);
      case AuthLandingDestination.expertProfile:
        widget.onExpertAuthenticated(context);
      case AuthLandingDestination.unsupportedRole:
        setState(() => _showsUnsupportedRole = true);
    }
  }

  void _returnToLogin() {
    setState(() {
      _onboardingSession = null;
      _showsUnsupportedRole = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showsUnsupportedRole) {
      return _UnsupportedRoleScreen(onBack: _returnToLogin);
    }

    final session = _onboardingSession;
    if (session != null) {
      return NewUserOnboardingFlowScreen(
        needsEmail: session.requiresAdditionalEmail,
        onBack: _returnToLogin,
        onComplete: _completeOnboarding,
      );
    }

    return SocialLoginScreen(onSignIn: _signIn);
  }
}

class _UnsupportedRoleScreen extends StatelessWidget {
  const _UnsupportedRoleScreen({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 52,
                color: AppColors.leaf,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                '아직 준비 중인 기능이에요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '1차 서비스에서는 보호자 기능을 먼저 제공해요.\n전문가 기능은 다음 버전에서 만날 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                key: const ValueKey('unsupported-role-back'),
                label: '로그인 화면으로 돌아가기',
                onPressed: onBack,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
