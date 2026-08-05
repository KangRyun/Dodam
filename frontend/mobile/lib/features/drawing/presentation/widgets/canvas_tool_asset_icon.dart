import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

enum CanvasToolArtwork { crayon, pencil, brush, eraser, fill, palette }

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
              // 원화 규격대로 마스크의 명암은 두고 선택 색을 곱한다. 색으로
              // 덮어쓰면 도구가 단색 덩어리가 되고, 밑그림 색이 가장자리로
              // 비쳐 나와 테두리에 분홍 띠가 생긴다.
              Image.asset(
                maskPath,
                key: ValueKey('canvas-tool-mask-${artwork.name}'),
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: filterQuality,
                color: pointColor,
                colorBlendMode: BlendMode.modulate,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
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
