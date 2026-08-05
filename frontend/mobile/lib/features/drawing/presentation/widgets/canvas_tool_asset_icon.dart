import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

enum CanvasToolArtwork { crayon, pencil, brush, eraser, fill, palette }

/// 도구 그림이다.
///
/// 색을 코드에서 입히지 않고 고른 색으로 미리 그려 둔 그림을 고른다. 한 장에
/// 색을 덧칠하면 마스크가 못 덮는 가장자리로 밑그림이 비쳐 테두리에 다른 색
/// 띠가 생긴다. 지우개와 팔레트는 선택 색을 따라가지 않는다.
final class CanvasToolAssetIcon extends StatelessWidget {
  const CanvasToolAssetIcon({
    required this.artwork,
    required this.pointColor,
    this.size = 40,
    this.filterQuality = FilterQuality.high,
    super.key,
  });

  final CanvasToolArtwork artwork;
  final Color pointColor;
  final double size;
  final FilterQuality filterQuality;

  /// 선택 색으로 미리 그려 둔 그림이 있는 도구다.
  static const _tinted = <CanvasToolArtwork, String>{
    CanvasToolArtwork.crayon: 'crayon',
    CanvasToolArtwork.pencil: 'pencil',
    CanvasToolArtwork.brush: 'brush',
    CanvasToolArtwork.fill: 'fill',
  };

  static const _fixed = <CanvasToolArtwork, String>{
    CanvasToolArtwork.eraser: 'assets/canvas/tools/eraser_base.png',
    CanvasToolArtwork.palette: 'assets/canvas/tools/palette_base.png',
  };

  static const _fallbackIcons = <CanvasToolArtwork, IconData>{
    CanvasToolArtwork.crayon: Icons.draw_outlined,
    CanvasToolArtwork.pencil: Icons.edit_outlined,
    CanvasToolArtwork.brush: Icons.brush_outlined,
    CanvasToolArtwork.eraser: Icons.cleaning_services_outlined,
    CanvasToolArtwork.fill: Icons.format_color_fill,
    CanvasToolArtwork.palette: Icons.palette_outlined,
  };

  /// 그림이 준비된 선택색이다. 팔레트에서 고른 중간색은 가장 가까운 것을 쓴다.
  static const _variants = <String, Color>{
    'red': AppColors.canvasSwatchRed,
    'orange': AppColors.canvasSwatchOrange,
    'yellow': AppColors.canvasSwatchYellow,
    'green': AppColors.canvasSwatchGreen,
    'teal': AppColors.canvasSwatchTeal,
    'blue': AppColors.canvasSwatchBlue,
    'purple': AppColors.canvasSwatchPurple,
    'charcoal': AppColors.canvasSwatchCharcoal,
  };

  @visibleForTesting
  static String variantFor(Color color) {
    var best = 'charcoal';
    var bestDistance = double.infinity;
    for (final entry in _variants.entries) {
      final distance =
          _square(color.r - entry.value.r) +
          _square(color.g - entry.value.g) +
          _square(color.b - entry.value.b);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry.key;
      }
    }
    return best;
  }

  static double _square(double value) => value * value;

  String get _assetPath {
    final tool = _tinted[artwork];
    if (tool == null) return _fixed[artwork]!;
    return 'assets/canvas/tools/${tool}_base.png';
  }

  String? get _maskPath {
    final tool = _tinted[artwork];
    return tool == null ? null : 'assets/canvas/tools/masks/${tool}_point.png';
  }

  double get _visualScale => switch (artwork) {
    CanvasToolArtwork.crayon => 1.12,
    CanvasToolArtwork.pencil => 1.04,
    CanvasToolArtwork.brush => 1.04,
    CanvasToolArtwork.fill => 1.03,
    CanvasToolArtwork.eraser || CanvasToolArtwork.palette => 1.12,
  };

  Offset get _visualOffset => switch (artwork) {
    CanvasToolArtwork.eraser ||
    CanvasToolArtwork.palette => Offset(0, size * .10),
    CanvasToolArtwork.crayon => Offset(0, size * .015),
    _ => Offset.zero,
  };

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: RepaintBoundary(
      key: ValueKey('canvas-tool-boundary-${artwork.name}'),
      child: Transform.translate(
        offset: _visualOffset,
        child: Transform.scale(
          scale: _visualScale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _assetPath,
                key: ValueKey('canvas-tool-base-${artwork.name}'),
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: filterQuality,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              ),
              if (_maskPath case final maskPath?)
                ColorFiltered(
                  colorFilter: ColorFilter.mode(pointColor, BlendMode.srcIn),
                  child: Image.asset(
                    maskPath,
                    key: ValueKey('canvas-tool-mask-${artwork.name}'),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: filterQuality,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _fallback() =>
      Icon(_fallbackIcons[artwork]!, size: size, color: AppColors.canvasInk);
}
