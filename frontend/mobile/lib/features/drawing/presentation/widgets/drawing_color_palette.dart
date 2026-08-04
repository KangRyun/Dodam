import 'dart:math' as math;

import 'package:dodam/design_system/tokens/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

final class DrawingColorPalette extends StatelessWidget {
  const DrawingColorPalette({
    required this.value,
    required this.previousColor,
    required this.onChanged,
    super.key,
  });

  final HSVColor value;
  final Color previousColor;
  final ValueChanged<HSVColor> onChanged;

  static const _horizontalPadding = 16.0;
  static const _hueTargetWidth = 48.0;
  static const _hueBarWidth = 40.0;
  static const _controlGap = 12.0;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('drawing-color-palette'),
    color: Colors.white,
    borderRadius: BorderRadius.circular(AppRadius.md),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(_horizontalPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 328.0;
          final planeWidth = math.max(
            180.0,
            availableWidth - _hueTargetWidth - _controlGap,
          );
          final planeHeight = math.min(220.0, planeWidth * .75);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SaturationValuePlane(
                    value: value,
                    width: planeWidth,
                    height: planeHeight,
                    onChanged: onChanged,
                  ),
                  const SizedBox(width: _controlGap),
                  _HueBar(
                    value: value,
                    height: planeHeight,
                    onChanged: onChanged,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ColorPreview(
                    key: const ValueKey('drawing-color-current'),
                    label: '현재 색상',
                    roleLabel: '현재',
                    color: value.toColor(),
                  ),
                  const SizedBox(width: 12),
                  _ColorPreview(
                    key: const ValueKey('drawing-color-previous'),
                    label: '이전 색상',
                    roleLabel: '이전',
                    color: previousColor,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

final class _SaturationValuePlane extends StatefulWidget {
  const _SaturationValuePlane({
    required this.value,
    required this.width,
    required this.height,
    required this.onChanged,
  });

  final HSVColor value;
  final double width;
  final double height;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<_SaturationValuePlane> createState() => _SaturationValuePlaneState();
}

final class _SaturationValuePlaneState extends State<_SaturationValuePlane> {
  static const _step = .05;
  static const _brighterAction = CustomSemanticsAction(label: '밝기 높이기');
  static const _darkerAction = CustomSemanticsAction(label: '밝기 낮추기');

  final FocusNode _focusNode = FocusNode(debugLabel: 'HSV saturation value');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _update(Offset position) {
    final saturation = (position.dx / widget.width).clamp(0.0, 1.0);
    final brightness = (1 - position.dy / widget.height).clamp(0.0, 1.0);
    widget.onChanged(
      widget.value.withSaturation(saturation).withValue(brightness),
    );
  }

  void _adjustSaturation(double delta) => widget.onChanged(
    widget.value.withSaturation(
      (widget.value.saturation + delta).clamp(0.0, 1.0),
    ),
  );

  void _adjustBrightness(double delta) => widget.onChanged(
    widget.value.withValue((widget.value.value + delta).clamp(0.0, 1.0)),
  );

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: _focusNode,
    onShowFocusHighlight: (focused) {
      if (_focused != focused) setState(() => _focused = focused);
    },
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowLeft): _AdjustSaturationIntent(
        -_step,
      ),
      SingleActivator(LogicalKeyboardKey.arrowRight): _AdjustSaturationIntent(
        _step,
      ),
      SingleActivator(LogicalKeyboardKey.arrowDown): _AdjustBrightnessIntent(
        -_step,
      ),
      SingleActivator(LogicalKeyboardKey.arrowUp): _AdjustBrightnessIntent(
        _step,
      ),
    },
    actions: <Type, Action<Intent>>{
      _AdjustSaturationIntent: CallbackAction<_AdjustSaturationIntent>(
        onInvoke: (intent) {
          _adjustSaturation(intent.delta);
          return null;
        },
      ),
      _AdjustBrightnessIntent: CallbackAction<_AdjustBrightnessIntent>(
        onInvoke: (intent) {
          _adjustBrightness(intent.delta);
          return null;
        },
      ),
    },
    child: Semantics(
      container: true,
      focusable: true,
      focused: _focused,
      label: '색상 채도와 밝기',
      value:
          '채도 ${(widget.value.saturation * 100).round()} 퍼센트, 밝기 ${(widget.value.value * 100).round()} 퍼센트',
      increasedValue:
          '채도 ${((widget.value.saturation + _step).clamp(0.0, 1.0) * 100).round()} 퍼센트',
      decreasedValue:
          '채도 ${((widget.value.saturation - _step).clamp(0.0, 1.0) * 100).round()} 퍼센트',
      onIncrease: () => _adjustSaturation(_step),
      onDecrease: () => _adjustSaturation(-_step),
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        _brighterAction: () => _adjustBrightness(_step),
        _darkerAction: () => _adjustBrightness(-_step),
      },
      child: GestureDetector(
        key: const ValueKey('hsv-saturation-value-plane'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          _focusNode.requestFocus();
          _update(details.localPosition);
        },
        onPanDown: (details) {
          _focusNode.requestFocus();
          _update(details.localPosition);
        },
        onPanUpdate: (details) => _update(details.localPosition),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SaturationValuePainter(hue: widget.value.hue),
                  ),
                ),
                Positioned(
                  left: widget.value.saturation * widget.width - 11,
                  top: (1 - widget.value.value) * widget.height - 11,
                  child: const IgnorePointer(child: _SelectionCursor()),
                ),
                if (_focused)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
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

final class _AdjustSaturationIntent extends Intent {
  const _AdjustSaturationIntent(this.delta);

  final double delta;
}

final class _AdjustBrightnessIntent extends Intent {
  const _AdjustBrightnessIntent(this.delta);

  final double delta;
}

final class _HueBar extends StatefulWidget {
  const _HueBar({
    required this.value,
    required this.height,
    required this.onChanged,
  });

  final HSVColor value;
  final double height;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<_HueBar> createState() => _HueBarState();
}

final class _HueBarState extends State<_HueBar> {
  static const _step = 5.0;

  final FocusNode _focusNode = FocusNode(debugLabel: 'HSV hue');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _update(Offset position) {
    final hue = (position.dy / widget.height).clamp(0.0, 1.0) * 360;
    widget.onChanged(widget.value.withHue(hue == 360 ? 0 : hue));
  }

  void _adjust(double delta) {
    final nextHue = (widget.value.hue + delta) % 360;
    widget.onChanged(widget.value.withHue(nextHue));
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: _focusNode,
    onShowFocusHighlight: (focused) {
      if (_focused != focused) setState(() => _focused = focused);
    },
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowUp): _AdjustHueIntent(-_step),
      SingleActivator(LogicalKeyboardKey.arrowLeft): _AdjustHueIntent(-_step),
      SingleActivator(LogicalKeyboardKey.arrowDown): _AdjustHueIntent(_step),
      SingleActivator(LogicalKeyboardKey.arrowRight): _AdjustHueIntent(_step),
    },
    actions: <Type, Action<Intent>>{
      _AdjustHueIntent: CallbackAction<_AdjustHueIntent>(
        onInvoke: (intent) {
          _adjust(intent.delta);
          return null;
        },
      ),
    },
    child: Semantics(
      container: true,
      focusable: true,
      focused: _focused,
      label: '색조',
      value: '${widget.value.hue.round()} 도',
      increasedValue: '${((widget.value.hue + _step) % 360).round()} 도',
      decreasedValue: '${((widget.value.hue - _step) % 360).round()} 도',
      onIncrease: () => _adjust(_step),
      onDecrease: () => _adjust(-_step),
      child: GestureDetector(
        key: const ValueKey('hsv-hue-slider'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          _focusNode.requestFocus();
          _update(details.localPosition);
        },
        onPanDown: (details) {
          _focusNode.requestFocus();
          _update(details.localPosition);
        },
        onPanUpdate: (details) => _update(details.localPosition),
        child: SizedBox(
          width: DrawingColorPalette._hueTargetWidth,
          height: widget.height,
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: DrawingColorPalette._hueBarWidth,
                  height: widget.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFF0000),
                                  Color(0xFFFFFF00),
                                  Color(0xFF00FF00),
                                  Color(0xFF00FFFF),
                                  Color(0xFF0000FF),
                                  Color(0xFFFF00FF),
                                  Color(0xFFFF0000),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 3,
                          right: 3,
                          top: widget.value.hue / 360 * widget.height - 3,
                          child: const IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.fromBorderSide(
                                  BorderSide(color: Colors.white, width: 2),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 1,
                                  ),
                                ],
                              ),
                              child: SizedBox(height: 6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black87, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _AdjustHueIntent extends Intent {
  const _AdjustHueIntent(this.delta);

  final double delta;
}

final class _SelectionCursor extends StatelessWidget {
  const _SelectionCursor();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('hsv-selection-cursor-outer'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: DecoratedBox(
        key: const ValueKey('hsv-selection-cursor-inner'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const SizedBox.square(dimension: 10),
      ),
    ),
  );
}

final class _ColorPreview extends StatelessWidget {
  const _ColorPreview({
    required this.label,
    required this.roleLabel,
    required this.color,
    super.key,
  });

  final String label;
  final String roleLabel;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: SizedBox(
      width: 96,
      height: 68,
      child: Column(
        children: [
          Expanded(
            child: SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black54, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            roleLabel,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

final class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) =>
      oldDelegate.hue != hue;
}
