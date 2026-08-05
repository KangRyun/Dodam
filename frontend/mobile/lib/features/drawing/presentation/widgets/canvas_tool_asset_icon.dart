import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

enum CanvasToolArtwork { crayon, pencil, brush, eraser, fill, palette }

final class CanvasToolAssetIcon extends StatelessWidget {
  const CanvasToolAssetIcon({
    required this.artwork,
    required this.pointColor,
    this.size = 40,
    this.filterQuality = FilterQuality.medium,
    super.key,
  });

  final CanvasToolArtwork artwork;
  final Color pointColor;
  final double size;
  final FilterQuality filterQuality;

  static const _fallbackIcons = <CanvasToolArtwork, IconData>{
    CanvasToolArtwork.crayon: Icons.draw_outlined,
    CanvasToolArtwork.pencil: Icons.edit_outlined,
    CanvasToolArtwork.brush: Icons.brush_outlined,
    CanvasToolArtwork.eraser: Icons.cleaning_services_outlined,
    CanvasToolArtwork.fill: Icons.format_color_fill,
    CanvasToolArtwork.palette: Icons.palette_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final basePath = _basePaths[artwork]!;
    final maskPath = _maskPaths[artwork];

    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        key: ValueKey('canvas-tool-boundary-${artwork.name}'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              basePath,
              key: ValueKey('canvas-tool-base-${artwork.name}'),
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: filterQuality,
              errorBuilder: (context, error, stackTrace) => _fallback(),
            ),
            if (maskPath != null)
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  colors: [pointColor, pointColor],
                ).createShader(bounds),
                child: Image.asset(
                  maskPath,
                  key: ValueKey('canvas-tool-mask-${artwork.name}'),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: filterQuality,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() =>
      Icon(_fallbackIcons[artwork]!, size: size, color: AppColors.canvasInk);
}

const _basePaths = <CanvasToolArtwork, String>{
  CanvasToolArtwork.crayon: 'assets/canvas/tools/crayon_base.png',
  CanvasToolArtwork.pencil: 'assets/canvas/tools/pencil_base.png',
  CanvasToolArtwork.brush: 'assets/canvas/tools/brush_base.png',
  CanvasToolArtwork.eraser: 'assets/canvas/tools/eraser_base.png',
  CanvasToolArtwork.fill: 'assets/canvas/tools/fill_base.png',
  CanvasToolArtwork.palette: 'assets/canvas/tools/palette_base.png',
};

const _maskPaths = <CanvasToolArtwork, String>{
  CanvasToolArtwork.crayon: 'assets/canvas/tools/masks/crayon_point.png',
  CanvasToolArtwork.pencil: 'assets/canvas/tools/masks/pencil_point.png',
  CanvasToolArtwork.brush: 'assets/canvas/tools/masks/brush_point.png',
  CanvasToolArtwork.fill: 'assets/canvas/tools/masks/fill_point.png',
};
