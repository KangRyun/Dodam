import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

enum DrawingCanvasDeviceClass { mobilePortrait, mobileLandscape, tablet }

final class DrawingCrayonFrame extends StatelessWidget {
  const DrawingCrayonFrame({
    required this.deviceClass,
    required this.child,
    super.key,
  });

  final DrawingCanvasDeviceClass deviceClass;
  final Widget child;

  bool get _isTablet => deviceClass == DrawingCanvasDeviceClass.tablet;

  @override
  Widget build(BuildContext context) {
    final frameAsset = _isTablet
        ? 'assets/canvas/frame/canvas_frame_tablet.png'
        : 'assets/canvas/frame/canvas_frame_mobile.png';
    final spiralAsset = _isTablet
        ? 'assets/canvas/frame/spiral_tablet.png'
        : 'assets/canvas/frame/spiral_mobile.png';
    final spiralCount = _isTablet ? 12 : 8;
    final spiralSize = _isTablet ? 32.0 : 22.0;

    return ColoredBox(
      key: const ValueKey('drawing-crayon-frame-exterior'),
      color: AppColors.canvasWarm,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(_isTablet ? 10 : 8),
            child: ColoredBox(
              key: const ValueKey('drawing-crayon-document'),
              color: Colors.white,
              child: child,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                frameAsset,
                key: const ValueKey('drawing-crayon-frame-nine-slice'),
                fit: BoxFit.fill,
                centerSlice: _isTablet
                    ? const Rect.fromLTRB(28, 28, 1230, 658)
                    : const Rect.fromLTRB(28, 28, 802, 274),
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Positioned(
            left: _isTablet ? 24 : 18,
            right: _isTablet ? 24 : 18,
            top: 0,
            height: spiralSize,
            child: IgnorePointer(
              key: const ValueKey('drawing-crayon-frame-spirals'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  spiralCount,
                  (_) => Image.asset(
                    spiralAsset,
                    width: spiralSize,
                    height: spiralSize,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
