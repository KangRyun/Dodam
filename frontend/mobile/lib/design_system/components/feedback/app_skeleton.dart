import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

/// 콘텐츠 로딩 자리표시자(스켈레톤) 공통 컴포넌트.
///
/// - 외부 shimmer 패키지 없이 [AnimationController] 기반 자체 시머로 구현한다.
///   (표준 [Alignment] 슬라이딩만 사용 — `Matrix4`/`GradientTransform` 미사용)
/// - 접근성: 모션 최소화(`MediaQuery.disableAnimations`)면 시머를 끄고 정적 표시,
///   스크린리더에는 낱개 블록을 읽지 않고 [AppSkeletonList]에서 '불러오는 중'만 한 번 알린다.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sm)),
    super.key,
  });

  /// 원형(썸네일·아바타 자리) 스켈레톤.
  const AppSkeleton.circle({required double size, Key? key})
    : this(
        width: size,
        height: size,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
        key: key,
      );

  /// 한 줄 텍스트 자리 스켈레톤.
  const AppSkeleton.line({double width = double.infinity, double height = 14, Key? key})
    : this(width: width, height: height, key: key);

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => _Shimmer(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: borderRadius,
      ),
    ),
  );
}

/// 리스트 로딩용 스켈레톤 묶음(썸네일 원형 + 제목·본문 두 줄 × N행).
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({
    this.itemCount = 4,
    this.hasThumbnail = true,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final int itemCount;
  final bool hasThumbnail;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '불러오는 중',
    child: ExcludeSemantics(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < itemCount; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              _SkeletonRow(hasThumbnail: hasThumbnail),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.hasThumbnail});

  final bool hasThumbnail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (hasThumbnail) ...[
        const AppSkeleton.circle(size: AppSizes.iconButton),
        const SizedBox(width: AppSpacing.md),
      ],
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton.line(width: 140, height: 14),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton.line(height: 12),
          ],
        ),
      ),
    ],
  );
}

/// 반복 시머 애니메이션을 [child] 위에 덧입히는 내부 위젯.
/// 모션 최소화 설정 시 애니메이션 없이 [child]를 그대로 반환한다.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final slide = _controller.value * 2 - 1; // -1.0 → 1.0 로 밝은 띠가 이동
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(slide - 1, 0),
            end: Alignment(slide + 1, 0),
            colors: const [
              AppColors.surfaceSoft,
              AppColors.surface,
              AppColors.surfaceSoft,
            ],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
