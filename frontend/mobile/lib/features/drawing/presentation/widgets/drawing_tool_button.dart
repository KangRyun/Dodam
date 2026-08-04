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
          dimension: 48,
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
                  if (widget.selected)
                    IgnorePointer(
                      child: Image.asset(
                        'assets/canvas/frame/selected_tool.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
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
                      size: 40,
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
