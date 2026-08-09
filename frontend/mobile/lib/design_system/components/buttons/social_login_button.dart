import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../../tokens/app_typography.dart';

enum SocialLoginProvider { kakao, google, naver }

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    required this.provider,
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final SocialLoginProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(provider);
    final enabled = onPressed != null && !isLoading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: visual.label,
      child: SizedBox(
        key: ValueKey('social-login-${provider.name}'),
        width: double.infinity,
        height: AppSizes.buttonHeight,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            backgroundColor: visual.background,
            foregroundColor: visual.foreground,
            disabledBackgroundColor: AppColors.disabled,
            disabledForegroundColor: AppColors.onDisabled,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(visual.borderRadius),
              side: BorderSide(color: visual.border),
            ),
          ),
          // 로고는 좌측에 고정하고 라벨은 버튼 전체 기준 가운데 정렬한다.
          // (좌측 아이콘 20 ↔ 우측 여백 20을 대칭으로 두어 텍스트가 정중앙에 온다.)
          child: isLoading
              ? CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: visual.foreground,
                )
              : Row(
                  children: [
                    SizedBox.square(
                      key: ValueKey('social-login-${provider.name}-icon'),
                      dimension: 20,
                      child: SvgPicture.asset(
                        visual.iconAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        visual.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTypography.button,
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SocialVisual {
  const _SocialVisual({
    required this.label,
    required this.iconAsset,
    required this.background,
    required this.foreground,
    required this.border,
    required this.borderRadius,
  });

  final String label;
  final String iconAsset;
  final Color background;
  final Color foreground;
  final Color border;
  final double borderRadius;
}

_SocialVisual _visualFor(SocialLoginProvider provider) => switch (provider) {
  SocialLoginProvider.kakao => const _SocialVisual(
    label: '카카오로 시작하기',
    iconAsset: 'assets/branding/kakao_symbol.svg',
    background: Color(0xFFFEE500),
    foreground: Color(0xD9000000),
    border: Colors.transparent,
    borderRadius: 12,
  ),
  SocialLoginProvider.google => const _SocialVisual(
    label: 'Google로 시작하기',
    iconAsset: 'assets/branding/google_g.svg',
    background: Colors.white,
    foreground: Color(0xFF1F1F1F),
    border: Color(0xFF747775),
    borderRadius: 12,
  ),
  SocialLoginProvider.naver => const _SocialVisual(
    label: '네이버로 시작하기',
    iconAsset: 'assets/branding/naver_n.svg',
    background: Color(0xFF03A94D),
    foreground: Colors.white,
    border: Colors.transparent,
    borderRadius: 12,
  ),
};
