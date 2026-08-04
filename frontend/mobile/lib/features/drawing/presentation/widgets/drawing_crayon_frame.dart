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
    // 스프링은 승인 시안(`styles.css` `.spiral-strip`)처럼 원본 크기 그대로
    // 가로로 반복한다. 개수를 고정해 균등 배치하면 화면 폭에 따라 간격이
    // 벌어져 시안보다 크고 성글게 보인다.
    final spiralWidth = _isTablet ? 38.0 : 29.0;
    final spiralHeight = _isTablet ? 46.0 : 36.0;
    final spiralOverhang = _isTablet ? 18.0 : 14.0;
    // 종이 질감 타일 크기도 시안 값(태블릿 320·모바일 240)에 맞춘다.
    final paperTextureScale = _isTablet ? 512 / 320 : 512 / 240;

    return ColoredBox(
      key: const ValueKey('drawing-crayon-frame-exterior'),
      color: AppColors.canvasWarm,
      child: Stack(
        fit: StackFit.expand,
        // 스프링이 스케치북 위쪽으로 걸쳐 나가야 시안과 같은 제본 모양이 된다.
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(_paperInset),
            child: ColoredBox(
              key: const ValueKey('drawing-crayon-document'),
              color: Colors.white,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: ExactAssetImage(
                      'assets/canvas/frame/paper_texture.png',
                      scale: paperTextureScale,
                    ),
                    repeat: ImageRepeat.repeat,
                    // 시안은 질감 위에 흰색 88% 를 덮는다. 남는 12% 가 결이다.
                    opacity: 0.12,
                  ),
                ),
                child: child,
              ),
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
            left: _spiralInset,
            right: _spiralInset,
            top: -spiralOverhang,
            height: spiralHeight,
            child: IgnorePointer(
              key: const ValueKey('drawing-crayon-frame-spirals'),
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tileCount = constraints.maxWidth <= 0
                        ? 0
                        : (constraints.maxWidth / spiralWidth).ceil();
                    return OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: double.infinity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          tileCount,
                          (_) => Image.asset(
                            spiralAsset,
                            width: spiralWidth,
                            height: spiralHeight,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 스케치북 테두리 선은 원화에서 가장자리 5px 안쪽에 그려져 있다. 종이도 같은
/// 위치에서 시작해야 시안처럼 선이 종이 경계에 붙는다.
const double _paperInset = 5;

/// 스프링이 모서리를 침범하지 않도록 좌우로 비우는 여백이다(시안 값).
const double _spiralInset = 21;
