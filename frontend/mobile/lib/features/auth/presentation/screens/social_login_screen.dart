import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/enums/auth_provider.dart';
import '../../domain/failures/auth_failure.dart';

typedef SocialSignInCallback = Future<void> Function(AuthProvider provider);

/// 넓은 화면에서 좌우 분할 레이아웃으로 전환하는 기준 폭.
/// 기존 auth 화면들과 동일한 700 기준을 사용한다.
const double _kTabletBreakpoint = 700;

/// 골드 히어로 위 텍스트 색(브랜드 워드마크·태그라인).
const Color _onHero = Color(0xFF5A3712);
const Color _onHeroSub = Color(0xFF8A5A1C);

const LinearGradient _heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.sunshine, AppColors.tangerine],
);

const String _mascotAsset = 'assets/characters/dodam_drawing.png';

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
        builder: (context, constraints) =>
            constraints.maxWidth >= _kTabletBreakpoint
            ? _buildTablet(context)
            : _buildMobile(context),
      ),
    ),
  );

  // 모바일: 상단 도담이 히어로 → 아래 흰 영역에 폼(세로 스택).
  Widget _buildMobile(BuildContext context) => Column(
    key: const ValueKey('login-layout-mobile'),
    children: [
      const _HeroBanner(),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _form(context, heading: const _TitleBlock()),
        ),
      ),
    ],
  );

  // 태블릿: 왼쪽 브랜드 패널 + 오른쪽 로그인 폼(좌우 분할).
  Widget _buildTablet(BuildContext context) => Row(
    key: const ValueKey('login-layout-tablet'),
    children: [
      const Expanded(flex: 46, child: _BrandPanel()),
      Expanded(
        flex: 54,
        child: ColoredBox(
          color: AppColors.surface,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _form(context, heading: const _WelcomeBlock()),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  // 모바일·태블릿이 공유하는 로그인 폼(제목·소셜 버튼·상태·안내).
  // 제목만 레이아웃별로 다르다(모바일=가치 문구 / 태블릿=반가워요).
  Widget _form(BuildContext context, {required Widget heading}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      heading,
      const SizedBox(height: AppSpacing.xl),
      const _SocialDivider(),
      const SizedBox(height: AppSpacing.md),
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
      const SizedBox(height: AppSpacing.md),
      const _SignupNote(),
      const SizedBox(height: AppSpacing.md),
      _ExpertGuideLink(onTap: widget.onExpertGuideTap),
      const SizedBox(height: AppSpacing.md),
      _PolicyNotice(
        onTermsTap: widget.onTermsTap,
        onPrivacyPolicyTap: widget.onPrivacyPolicyTap,
      ),
    ],
  );
}

/// 모바일 상단 히어로 — 골드 배경 위 그림 그리는 도담이.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.40).clamp(
      220.0,
      320.0,
    );
    return ClipPath(
      clipper: _HeroWaveClipper(),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(gradient: _heroGradient),
        alignment: Alignment.bottomCenter,
        // 물결에 그림이 잘리지 않도록 아래 여백을 둔다.
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.lg,
        ),
        child: Image.asset(
          _mascotAsset,
          fit: BoxFit.contain,
          semanticLabel: '그림 그리는 도담이',
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 히어로 하단을 부드러운 물결로 잘라내는 클리퍼.
class _HeroWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 26)
      ..quadraticBezierTo(w * 0.25, h, w * 0.5, h - 18)
      ..quadraticBezierTo(w * 0.75, h - 38, w, h - 24)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 태블릿 우측 폼 제목 — 반가워요.
class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '반가워요',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      SizedBox(height: AppSpacing.xs),
      Text(
        '소셜 계정으로 로그인하고 도담을 시작해요.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 14, height: 1.5),
      ),
    ],
  );
}

/// 소셜 전용 가입 안내.
class _SignupNote extends StatelessWidget {
  const _SignupNote();

  @override
  Widget build(BuildContext context) => const Text(
    '회원가입도 소셜 로그인으로 진행돼요',
    textAlign: TextAlign.center,
    style: TextStyle(
      color: AppColors.inkMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// 태블릿 좌측 브랜드 패널 — 도담 워드마크 + 배경에 둥둥 떠다니는 손그림 + 도담이.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: _heroGradient),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 손그림 크기는 패널 폭 비율로 두되 과도하게 커지지 않게 제한한다.
        double doodle(double factor) => (w * factor).clamp(40.0, 190.0);
        // Stack 기본 클립으로 손그림이 패널 밖으로 새지 않는다.
        return Stack(
          children: [
            // 배경 손그림 — 크기·위치·속도를 서로 다르게 둬 자연스럽게 떠다닌다.
            Positioned(
              left: w * 0.44,
              top: h * 0.17,
              width: doodle(0.135),
              child: const _FloatingDoodle(
                asset: 'assets/characters/doodle_tree.png',
                period: Duration(milliseconds: 8000),
                dy: -8,
              ),
            ),
            Positioned(
              left: w * 0.02,
              top: h * 0.27,
              width: doodle(0.29),
              child: const _FloatingDoodle(
                asset: 'assets/characters/doodle_dino.png',
                period: Duration(milliseconds: 6000),
                dx: 6,
                dy: -12,
              ),
            ),
            Positioned(
              left: w * 0.57,
              top: h * 0.36,
              width: doodle(0.35),
              child: const _FloatingDoodle(
                asset: 'assets/characters/doodle_sun.png',
                period: Duration(milliseconds: 7000),
                dy: -16,
              ),
            ),
            const Positioned(
              left: AppSpacing.xl,
              top: AppSpacing.xxl,
              child: _HeroWordmark(),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 0.82,
                child: Image.asset(
                  _mascotAsset,
                  fit: BoxFit.contain,
                  semanticLabel: '그림 그리는 도담이',
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 배경에서 상하(및 약간의 좌우)로 부드럽게 떠다니는 손그림.
/// 시스템 애니메이션 최소화(reduce motion)면 정지한다.
class _FloatingDoodle extends StatefulWidget {
  const _FloatingDoodle({
    required this.asset,
    required this.period,
    this.dx = 0,
    this.dy = -12,
  });

  final String asset;
  final Duration period;
  final double dx;
  final double dy;

  @override
  State<_FloatingDoodle> createState() => _FloatingDoodleState();
}

class _FloatingDoodleState extends State<_FloatingDoodle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, child) => Transform.translate(
      offset: Offset(widget.dx * _progress.value, widget.dy * _progress.value),
      child: child,
    ),
    child: Image.asset(
      widget.asset,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
  );
}

class _HeroWordmark extends StatelessWidget {
  const _HeroWordmark();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '도담',
        style: TextStyle(
          color: _onHero,
          fontSize: 40,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
        ),
      ),
      SizedBox(height: AppSpacing.xs),
      Text(
        '그림으로 시작하는\n우리 아이와의 대화',
        style: TextStyle(
          color: _onHeroSub,
          fontSize: 15,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

/// 제목·부제 — 모바일·태블릿 폼 공통.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '그림과 대화로\n아이의 마음을 만나봐요',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 24,
          height: 1.32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      SizedBox(height: AppSpacing.sm),
      Text(
        '아이가 편안하게 마음을 표현하도록\n도담이가 곁에서 함께할게요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkMuted, fontSize: 14, height: 1.5),
      ),
    ],
  );
}

/// "소셜 계정으로 시작" 구분선.
class _SocialDivider extends StatelessWidget {
  const _SocialDivider();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: Divider(color: AppColors.outline, thickness: 1)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Text(
          '소셜 계정으로 시작',
          style: TextStyle(
            color: AppColors.inkMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(child: Divider(color: AppColors.outline, thickness: 1)),
    ],
  );
}

class _LoginProgress extends StatelessWidget {
  const _LoginProgress({required this.provider});

  final AuthProvider provider;

  @override
  Widget build(BuildContext context) {
    final message = '${_providerLabel(provider)} 계정으로 연결하고 있어요…';
    return Semantics(
      liveRegion: true,
      label: message,
      child: Padding(
        key: const ValueKey('login-progress'),
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LoginFailurePanel extends StatelessWidget {
  const _LoginFailurePanel({required this.failure, this.onRetry});

  final AuthFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _failureMessage(failure.type);
    return Semantics(
      liveRegion: true,
      label: '로그인을 완료하지 못했어요. $message',
      child: Container(
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
                    message,
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
      ),
    );
  }
}

String _providerLabel(AuthProvider provider) => switch (provider) {
  AuthProvider.kakao => '카카오',
  AuthProvider.google => '구글',
  AuthProvider.naver => '네이버',
};

String _failureMessage(AuthFailureType type) => switch (type) {
  AuthFailureType.network => '인터넷 연결이 불안정해요.\n연결을 확인한 뒤 다시 시도해 주세요.',
  AuthFailureType.serverRejected => '잠시 로그인 서비스를 이용하기 어려워요. 잠시 후 다시 시도해 주세요.',
  AuthFailureType.providerRejected ||
  AuthFailureType.invalidCredential ||
  AuthFailureType.tokenExpired => '로그인 정보를 확인하지 못했어요. 다시 로그인해 주세요.',
  AuthFailureType.configuration => '앱 로그인 설정을 확인해 주세요. 문제가 계속되면 관리자에게 문의해 주세요.',
  AuthFailureType.accountSuspended ||
  AuthFailureType.accountWithdrawn => '이 계정으로는 로그인할 수 없어요. 고객센터에 문의해 주세요.',
  AuthFailureType.cancelled => '로그인이 취소됐어요.',
  AuthFailureType.unknown => '예상하지 못한 문제가 발생했어요. 다시 시도해 주세요.',
};

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
