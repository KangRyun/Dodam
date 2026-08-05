import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

const guardianReauthSheetKey = ValueKey('guardian-reauth-sheet');
const guardianReauthCancelKey = ValueKey('guardian-reauth-cancel');

/// PIN 재설정 전 본인확인에 쓸 소셜 제공자를 고르게 한다(S15P11B209-874).
///
/// 고른 제공자를 돌려주고, 닫히거나 취소하면 `null`을 돌려준다. 실제 재로그인과
/// 계정 동일성 판정은 호출자(앱 셸)가 한다 — 이 위젯은 인증 경계를 모른다.
Future<SocialLoginProvider?> showGuardianReauthSheet(BuildContext context) =>
    showModalBottomSheet<SocialLoginProvider>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => const _GuardianReauthSheet(),
    );

final class _GuardianReauthSheet extends StatelessWidget {
  const _GuardianReauthSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    key: guardianReauthSheetKey,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '보호자 본인 확인',
                textAlign: TextAlign.center,
                style: AppTypography.titleMd,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'PIN을 새로 설정하려면 지금 로그인된 계정으로 한 번 더 로그인해 주세요.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final provider in SocialLoginProvider.values) ...[
                SocialLoginButton(
                  provider: provider,
                  onPressed: () => Navigator.of(context).pop(provider),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: AppSizes.minTouchTarget,
                child: TextButton(
                  key: guardianReauthCancelKey,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '취소',
                    style: AppTypography.button.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
