import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

typedef AuthSignOut = Future<void> Function();
typedef AuthSignedOutNavigation = void Function(BuildContext context);

class LogoutActionButton extends StatefulWidget {
  const LogoutActionButton({
    required this.onSignOut,
    required this.onSignedOut,
    super.key,
  });

  final AuthSignOut onSignOut;
  final AuthSignedOutNavigation onSignedOut;

  @override
  State<LogoutActionButton> createState() => _LogoutActionButtonState();
}

class _LogoutActionButtonState extends State<LogoutActionButton> {
  bool _isSigningOut = false;

  // 로그아웃 확인 후 인증 정보 초기화
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
      if (mounted) widget.onSignedOut(context);
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.xs),
    child: IconButton(
      key: const ValueKey('logout-action'),
      tooltip: '로그아웃',
      onPressed: _isSigningOut ? null : _signOut,
      icon: _isSigningOut
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout_rounded),
    ),
  );
}
