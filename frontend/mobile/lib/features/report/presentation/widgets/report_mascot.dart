import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

abstract final class ReportMascotAssets {
  static const String intro = 'assets/characters/report_mascot_intro.png';
  static const String observe = 'assets/characters/report_mascot_observe.png';
  static const String complete = 'assets/characters/report_mascot_complete.png';
}

/// 리포트 안내 캐릭터는 장식으로만 표시한다.
///
/// asset이 누락되거나 decode되지 않아도 같은 공간의 본문과 행동 버튼은 유지한다.
class ReportMascotImage extends StatelessWidget {
  const ReportMascotImage({
    required this.assetPath,
    required this.maxWidth,
    required this.mascotKey,
    super.key,
  });

  final String assetPath;
  final double maxWidth;
  final Key mascotKey;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : maxWidth;
        final width = availableWidth.clamp(0.0, maxWidth).toDouble();
        return SizedBox(
          key: mascotKey,
          width: width,
          child: AspectRatio(
            aspectRatio: 480 / 560,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const _MascotFallback(),
            ),
          ),
        );
      },
    ),
  );
}

class _MascotFallback extends StatelessWidget {
  const _MascotFallback();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(
      Icons.auto_awesome_rounded,
      key: ValueKey('report-mascot-fallback'),
      color: AppColors.sunshine,
      size: 40,
    ),
  );
}
