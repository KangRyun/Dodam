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

    // 테두리 원화의 둥근 모서리 반지름이다. 종이를 같은 값으로 잘라야 흰 모서리가
    // 선 밖으로 삐져나오지 않는다.
    final paperRadius = Radius.circular((_isTablet ? 20 : 15) - _paperInset);

    return ColoredBox(
      key: const ValueKey('drawing-crayon-frame-exterior'),
      // 테두리 선 바깥은 화면 배경이 그대로 보여야 한다. 여기에 색을 깔면 선
      // 밖으로 밝은 띠가 둘려 종이가 테두리를 넘어선 것처럼 보인다.
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        // 스프링이 스케치북 위쪽으로 걸쳐 나가야 시안과 같은 제본 모양이 된다.
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(_paperInset),
            child: ClipRRect(
              borderRadius: BorderRadius.all(paperRadius),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 들어가는 만큼만 온전히 놓고 남는 폭은 사이사이로 나눈다.
                  // 잘라 내면 오른쪽 끝 스프링이 반토막 난 채로 남는다.
                  final tileCount = constraints.maxWidth <= 0
                      ? 0
                      : (constraints.maxWidth / spiralWidth).floor();
                  if (tileCount <= 0) return const SizedBox.shrink();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  );
                },
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
