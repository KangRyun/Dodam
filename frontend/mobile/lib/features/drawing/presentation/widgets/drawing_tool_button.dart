import 'package:flutter/material.dart';

import 'canvas_tool_asset_icon.dart';

final class DrawingToolButton extends StatefulWidget {
  const DrawingToolButton({
    required this.artwork,
    required this.pointColor,
    required this.selected,
    required this.semanticLabel,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final CanvasToolArtwork artwork;
  final Color pointColor;
  final bool selected;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<DrawingToolButton> createState() => _DrawingToolButtonState();
}

/// 손가락으로 누를 수 있는 최소 크기다. 툴바가 좁아져도 줄이지 않는다.
const double _buttonSize = 48;

/// 도구 그림 크기다. 승인 시안의 버튼:그림 비율(62:47)을 따른다.
const double _artworkSize = 42;

/// 선택 받침 크기다. 크레용·붓처럼 비스듬히 놓인 그림은 상자 모서리까지 꽉 차서,
/// 받침이 버튼과 같은 크기면 그림이 받침 밖으로 삐져나온 것처럼 보인다.
const double _plateSize = 66;

final class _DrawingToolButtonState extends State<DrawingToolButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final emphasized = widget.selected || _hovered || _focused;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        label: widget.semanticLabel,
        button: true,
        selected: widget.selected,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: _buttonSize,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              excludeFromSemantics: true,
              customBorder: const CircleBorder(),
              mouseCursor: SystemMouseCursors.click,
              onHover: (value) {
                if (_hovered != value) setState(() => _hovered = value);
              },
              onFocusChange: (value) {
                if (_focused != value) setState(() => _focused = value);
              },
              onTap: widget.onPressed,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 선택 판은 버튼을 가득 채워야 도구 그림을 감싸는 받침으로
                  // 읽힌다. 그림보다 조금만 크면 뒤에 낀 상자처럼 보인다.
                  if (widget.selected)
                    IgnorePointer(
                      child: OverflowBox(
                        maxWidth: _plateSize,
                        maxHeight: _plateSize,
                        child: Image.asset(
                          'assets/canvas/frame/selected_tool.png',
                          width: _plateSize,
                          height: _plateSize,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  AnimatedScale(
                    key: ValueKey(
                      'drawing-tool-artwork-${widget.artwork.name}',
                    ),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    scale: emphasized ? 1.06 : 1,
                    child: CanvasToolAssetIcon(
                      artwork: widget.artwork,
                      pointColor: widget.pointColor,
                      size: _artworkSize,
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
