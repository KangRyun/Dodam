import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 아이 등록/편집 화면 전용 크레용 스킨 부품(S15P11B209-943).
///
/// 공용 컴포넌트(`AppTextField`·`AppButton`·`AppChoiceCard`)는 다른 화면도 쓰므로
/// 건드리지 않고, 이 화면에서만 쓰는 표시 전용 위젯을 여기에 모았다. 값·검증·
/// 저장 로직은 화면이 그대로 들고 있고 여기서는 그리기만 한다.
abstract final class CrayonPalette {
  /// 크레용 윤곽선. 화면 본문 잉크(`AppColors.ink`)보다 살짝 따뜻하다.
  static const outline = Color(0xFF4A4038);
  static const cardFill = Color(0xFFFFFDF6);

  /// 난이도 1단계 — 초록.
  static const easyFill = AppColors.leaf;
  static const easyStrong = AppColors.leafPressed;
  static const easyTint = AppColors.leafSoft;

  /// 난이도 2단계 — 앰버.
  static const midFill = Color(0xFFF2B84B);
  static const midStrong = AppColors.warning;
  static const midTint = AppColors.warningSoft;

  /// 난이도 3단계 — 코랄.
  static const hardFill = Color(0xFFE8896B);
  static const hardStrong = Color(0xFFC96548);
  static const hardTint = Color(0xFFFDF2EC);
}

/// 손으로 그린 듯 모서리마다 곡률이 다른 사각형.
const crayonCardRadius = BorderRadius.only(
  topLeft: Radius.elliptical(28, 18),
  topRight: Radius.elliptical(16, 26),
  bottomRight: Radius.elliptical(26, 16),
  bottomLeft: Radius.elliptical(18, 28),
);

/// 알약처럼 길쭉하되 좌우 곡률이 어긋난 버튼용 모서리.
const crayonPillRadius = BorderRadius.only(
  topLeft: Radius.elliptical(40, 16),
  topRight: Radius.elliptical(16, 40),
  bottomRight: Radius.elliptical(40, 16),
  bottomLeft: Radius.elliptical(16, 40),
);

/// 크레용 테두리 + 살짝 어긋난 그림자를 두른 카드.
class CrayonCard extends StatelessWidget {
  const CrayonCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    this.background = CrayonPalette.cardFill,
    this.borderColor = CrayonPalette.outline,
    this.borderWidth = 2.5,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: crayonCardRadius,
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A4A4038),
          offset: Offset(2, 3),
          blurRadius: 0,
        ),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// 제목 아래에 크레용 물결 밑줄을 긋는 섹션 머리말.
class CrayonSectionTitle extends StatelessWidget {
  const CrayonSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Align(
      alignment: Alignment.centerLeft,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            const SizedBox(
              height: 7,
              width: double.infinity,
              child: CustomPaint(painter: _CrayonUnderlinePainter()),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CrayonUnderlinePainter extends CustomPainter {
  const _CrayonUnderlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final paint = Paint()
      ..color = AppColors.sunshine
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final baseline = size.height * 0.6;
    final path = Path()..moveTo(1, baseline);
    const segment = 26.0;
    var x = 1.0;
    var up = true;
    while (x < size.width - 1) {
      final next = math.min(x + segment, size.width - 1);
      path.quadraticBezierTo(
        (x + next) / 2,
        up ? 0 : size.height,
        next,
        baseline,
      );
      up = !up;
      x = next;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CrayonUnderlinePainter oldDelegate) => false;
}

/// 난이도를 칸 수로 보여주는 채우기 미터.
///
/// 색만으로 단계를 나타내지 않도록 **채운 칸 수**가 곧 단계다. 읽는 의미는 옆의
/// 텍스트 라벨이 전달하므로 여기서는 semantics를 내지 않는다.
class CrayonMeter extends StatelessWidget {
  const CrayonMeter({
    required this.filled,
    required this.total,
    required this.color,
    required this.strongColor,
    super.key,
  });

  final int filled;
  final int total;
  final Color color;
  final Color strongColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < total; index++) ...[
          if (index > 0) const SizedBox(width: 5),
          Container(
            width: 14,
            height: 32,
            decoration: BoxDecoration(
              color: index < filled ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: index < filled ? strongColor : AppColors.outlineStrong,
                width: 2.5,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 크레용 스킨 버튼. 채움(제출)·외곽선(보조·위험) 세 가지 결을 낸다.
enum CrayonButtonVariant { filled, outline, danger }

class CrayonButton extends StatelessWidget {
  const CrayonButton({
    required this.label,
    required this.onPressed,
    this.variant = CrayonButtonVariant.filled,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final CrayonButtonVariant variant;
  final Widget? icon;
  final bool isLoading;

  Color get _background => switch (variant) {
    CrayonButtonVariant.filled => AppColors.sunshine,
    CrayonButtonVariant.outline => AppColors.leafSoft,
    CrayonButtonVariant.danger => AppColors.errorSoft,
  };

  Color get _border => switch (variant) {
    CrayonButtonVariant.filled => const Color(0xFFE0B53F),
    CrayonButtonVariant.outline => AppColors.leaf,
    CrayonButtonVariant.danger => AppColors.error,
  };

  Color get _foreground => switch (variant) {
    CrayonButtonVariant.filled => const Color(0xFF5A3712),
    CrayonButtonVariant.outline => AppColors.leafPressed,
    CrayonButtonVariant.danger => AppColors.error,
  };

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: enabled ? _background : AppColors.disabled,
        shape: RoundedRectangleBorder(
          borderRadius: crayonPillRadius,
          side: BorderSide(
            color: enabled ? _border : AppColors.outlineStrong,
            width: 2.5,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          customBorder: RoundedRectangleBorder(borderRadius: crayonPillRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading) ...[
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: enabled ? _foreground : AppColors.onDisabled,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ] else if (icon != null) ...[
                    IconTheme.merge(
                      data: IconThemeData(size: 20, color: _foreground),
                      child: icon!,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: enabled ? _foreground : AppColors.onDisabled,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진 자리에 두르는 크레용 점선 링.
class CrayonPhotoRing extends StatelessWidget {
  const CrayonPhotoRing({required this.child, this.diameter = 132, super.key});

  final Widget child;
  final double diameter;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: const _CrayonRingPainter(),
    child: SizedBox.square(dimension: diameter, child: child),
  );
}

class _CrayonRingPainter extends CustomPainter {
  const _CrayonRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2B74E)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final radius = (math.min(size.width, size.height) / 2) - 1.5;
    final center = Offset(size.width / 2, size.height / 2);
    // 점선 원. 크레용으로 툭툭 끊어 그린 결을 낸다.
    const dash = 0.16;
    const gap = 0.09;
    for (var angle = 0.0; angle < math.pi * 2; angle += dash + gap) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dash,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CrayonRingPainter oldDelegate) => false;
}
