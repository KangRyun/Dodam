import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/auth_landing_resolver.dart';
import '../../domain/entities/auth_session.dart';

typedef AuthSessionRestore = Future<AuthSession?> Function();
typedef AuthBootstrapNavigation = void Function(BuildContext context);

class AuthBootstrapScreen extends StatefulWidget {
  const AuthBootstrapScreen({
    required this.restoreSession,
    required this.onProfileSelectionRequired,
    required this.onExpertAuthenticated,
    required this.onLoginRequired,
    super.key,
  });

  final AuthSessionRestore restoreSession;
  final AuthBootstrapNavigation onProfileSelectionRequired;
  final AuthBootstrapNavigation onExpertAuthenticated;
  final AuthBootstrapNavigation onLoginRequired;

  @override
  State<AuthBootstrapScreen> createState() => _AuthBootstrapScreenState();
}

class _AuthBootstrapScreenState extends State<AuthBootstrapScreen> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  // 저장된 인증 상태에 따른 최초 화면 결정
  Future<void> _restore() async {
    final session = await widget.restoreSession();
    if (!mounted) return;

    final destination = session == null || session.requiresOnboarding
        ? null
        : AuthLandingResolver.resolve(session.user.role);
    switch (destination) {
      case AuthLandingDestination.profileSelection:
        widget.onProfileSelectionRequired(context);
        return;
      case AuthLandingDestination.expertProfile:
        widget.onExpertAuthenticated(context);
        return;
      case AuthLandingDestination.unsupportedRole || null:
        widget.onLoginRequired(context);
        return;
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: Center(child: AppLoadingView(message: '로그인 정보를 확인하고 있어요')),
    ),
  );
}
