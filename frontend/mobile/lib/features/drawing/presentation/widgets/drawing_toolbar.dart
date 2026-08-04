import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

import '../../application/drawing_sync_coordinator.dart';
import '../models/drawing_tool_state.dart';
import 'canvas_tool_asset_icon.dart';
import 'drawing_crayon_frame.dart';
import 'drawing_tool_button.dart';

final class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({
    required this.toolState,
    required this.quickColors,
    required this.paletteAnchorLink,
    required this.onBack,
    required this.canUndo,
    required this.canRedo,
    required this.canComplete,
    required this.isCompleting,
    required this.saveStatus,
    required this.onUndo,
    required this.onRedo,
    required this.onRetrySave,
    required this.onInstrumentChanged,
    required this.onEraserMenuAction,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpenPalette,
    required this.onComplete,
    super.key,
  });

  final DrawingToolState toolState;
  final List<Color> quickColors;
  final LayerLink paletteAnchorLink;
  final VoidCallback onBack;
  final bool canUndo;
  final bool canRedo;
  final bool canComplete;
  final bool isCompleting;
  final DrawingSaveStatus saveStatus;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onRetrySave;
  final ValueChanged<DrawingInstrument> onInstrumentChanged;
  final ValueChanged<DrawingEraserMenuAction> onEraserMenuAction;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final VoidCallback onOpenPalette;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final deviceClass = _deviceClassFor(MediaQuery.sizeOf(context));
    final primaryActions = _primaryActions(context);

    return switch (deviceClass) {
      DrawingCanvasDeviceClass.mobilePortrait => SizedBox(
        key: const ValueKey('drawing-toolbar'),
        height: 112,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: _ToolbarChrome(
                deviceClass: deviceClass,
                child: Row(
                  key: const ValueKey('drawing-toolbar-primary-row'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: primaryActions.take(6).toList(growable: false),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: _ToolbarChrome(
                deviceClass: deviceClass,
                child: Row(
                  children: [
                    ...primaryActions.skip(6),
                    Expanded(child: _secondaryControls()),
                    _ToolbarSaveStatus(
                      status: saveStatus,
                      onRetry: onRetrySave,
                      width: 112,
                    ),
                    _completeButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      DrawingCanvasDeviceClass.mobileLandscape => _singleRow(
        context,
        deviceClass: deviceClass,
        height: 60,
      ),
      DrawingCanvasDeviceClass.tablet => _singleRow(
        context,
        deviceClass: deviceClass,
        height: 72,
      ),
    };
  }

  Widget _singleRow(
    BuildContext context, {
    required DrawingCanvasDeviceClass deviceClass,
    required double height,
  }) => SizedBox(
    key: const ValueKey('drawing-toolbar'),
    height: height,
    child: _ToolbarChrome(
      deviceClass: deviceClass,
      child: Row(
        key: const ValueKey('drawing-toolbar-single-row'),
        children: [
          ..._primaryActions(context),
          Expanded(child: _secondaryControls()),
          _ToolbarSaveStatus(
            status: saveStatus,
            onRetry: onRetrySave,
            width: deviceClass == DrawingCanvasDeviceClass.tablet ? 128 : 116,
          ),
          _completeButton(),
        ],
      ),
    ),
  );

  List<Widget> _primaryActions(BuildContext context) => [
    _ToolbarAssetAction(
      key: const ValueKey('drawing-back'),
      assetPath: 'assets/canvas/frame/back.png',
      semanticLabel: '뒤로 가기',
      tooltip: '뒤로 가기',
      onPressed: onBack,
    ),
    _ToolbarAssetAction(
      key: const ValueKey('undo-action'),
      assetPath: 'assets/canvas/frame/undo.png',
      semanticLabel: '실행 취소',
      tooltip: '실행 취소',
      onPressed: canUndo ? onUndo : null,
    ),
    _ToolbarAssetAction(
      key: const ValueKey('redo-action'),
      assetPath: 'assets/canvas/frame/redo.png',
      semanticLabel: '다시 실행',
      tooltip: '다시 실행',
      onPressed: canRedo ? onRedo : null,
    ),
    _instrumentButton(
      instrument: DrawingInstrument.crayon,
      artwork: CanvasToolArtwork.crayon,
      label: '크레용',
    ),
    _instrumentButton(
      instrument: DrawingInstrument.pencil,
      artwork: CanvasToolArtwork.pencil,
      label: '연필',
    ),
    _instrumentButton(
      instrument: DrawingInstrument.brush,
      artwork: CanvasToolArtwork.brush,
      label: '브러시',
    ),
    Builder(
      builder: (anchorContext) => DrawingToolButton(
        key: const ValueKey('drawing-tool-eraser'),
        artwork: CanvasToolArtwork.eraser,
        pointColor: toolState.color,
        selected: toolState.instrument == DrawingInstrument.eraser,
        semanticLabel: '지우개 도구',
        tooltip: '지우개',
        onPressed: () {
          onInstrumentChanged(DrawingInstrument.eraser);
          _showEraserMenu(anchorContext);
        },
      ),
    ),
    _instrumentButton(
      instrument: DrawingInstrument.fill,
      artwork: CanvasToolArtwork.fill,
      label: '채우기',
    ),
  ];

  Widget _instrumentButton({
    required DrawingInstrument instrument,
    required CanvasToolArtwork artwork,
    required String label,
  }) {
    final button = DrawingToolButton(
      key: ValueKey('drawing-tool-${instrument.name}'),
      artwork: artwork,
      pointColor: toolState.color,
      selected: toolState.instrument == instrument,
      semanticLabel: '$label 도구',
      tooltip: label,
      onPressed: () => onInstrumentChanged(instrument),
    );
    if (instrument != DrawingInstrument.crayon) return button;
    return KeyedSubtree(key: const ValueKey('drawing-tool-pen'), child: button);
  }

  Future<void> _showEraserMenu(BuildContext context) async {
    final anchor = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<DrawingEraserMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        topLeft & anchor.size,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: ValueKey('drawing-eraser-stroke'),
          value: DrawingEraserMenuAction.selectStroke,
          child: Text('선 지우개'),
        ),
        PopupMenuItem(
          key: ValueKey('drawing-eraser-area'),
          value: DrawingEraserMenuAction.selectArea,
          child: Text('영역 지우개'),
        ),
        PopupMenuItem(
          key: ValueKey('drawing-eraser-clear-all'),
          value: DrawingEraserMenuAction.clearAll,
          child: Text('전체 지우기'),
        ),
      ],
    );
    if (selected != null) onEraserMenuAction(selected);
  }

  Widget _secondaryControls() => SingleChildScrollView(
    key: const ValueKey('drawing-toolbar-secondary-row'),
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          key: const ValueKey('drawing-quick-colors'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < quickColors.length; index++)
              KeyedSubtree(
                key: index < _quickColorNames.length
                    ? ValueKey('color-${_quickColorNames[index]}')
                    : null,
                child: _QuickColorButton(
                  key: ValueKey('drawing-quick-color-$index'),
                  index: index,
                  assetPath: _quickColorAssetPaths[index],
                  selected:
                      quickColors[index].toARGB32() ==
                      toolState.color.toARGB32(),
                  onPressed: () => onColorChanged(quickColors[index]),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        SizedBox(
          key: const ValueKey('drawing-thickness-slider'),
          width: 116,
          height: 48,
          child: Semantics(
            label: '선 굵기',
            value: toolState.width.toStringAsFixed(0),
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 6,
                overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppColors.canvasInk,
                inactiveTrackColor: AppColors.canvasBorderStrong,
                thumbColor: AppColors.canvasInk,
              ),
              child: Slider(
                value: toolState.width.clamp(1, 40),
                min: 1,
                max: 40,
                onChanged: onWidthChanged,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 굵기 프리셋은 슬라이더 바로 옆에 둔다. 팔레트 뒤에 두면 툴바가 좁은
        // 기기에서 스크롤 밖으로 밀려 아이 눈에 보이지 않는다.
        for (final (label, width) in _thicknessPresets)
          _ThicknessPresetButton(
            key: ValueKey('drawing-thickness-$label'),
            label: label,
            selected: toolState.width == width,
            onPressed: () => onWidthChanged(width),
          ),
        const SizedBox(width: 8),
        // 지금 굵기와 색은 팔레트 버튼이 함께 보여 준다. 따로 미리보기 점을
        // 두면 툴바가 넘쳐 팔레트 버튼이 화면 밖으로 밀린다.
        SizedBox.square(
          key: const ValueKey('drawing-thickness-preview'),
          dimension: 32,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: toolState.color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.canvasInk),
              ),
              child: SizedBox.square(dimension: toolState.width.clamp(4, 24)),
            ),
          ),
        ),
        const SizedBox(width: 4),
        CompositedTransformTarget(
          link: paletteAnchorLink,
          child: DrawingToolButton(
            key: const ValueKey('drawing-palette-button'),
            artwork: CanvasToolArtwork.palette,
            pointColor: toolState.color,
            selected: false,
            semanticLabel: '색상 팔레트 버튼',
            tooltip: '색상 팔레트',
            onPressed: onOpenPalette,
          ),
        ),
      ],
    ),
  );

  static const _quickColorNames = [
    '빨강',
    '주황',
    '노랑',
    '초록',
    '청록',
    '파랑',
    '보라',
    '검정',
  ];
  static const _quickColorAssetPaths = <String>[
    'assets/canvas/swatches/red.png',
    'assets/canvas/swatches/orange.png',
    'assets/canvas/swatches/yellow.png',
    'assets/canvas/swatches/green.png',
    'assets/canvas/swatches/teal.png',
    'assets/canvas/swatches/blue.png',
    'assets/canvas/swatches/purple.png',
    'assets/canvas/swatches/charcoal.png',
  ];
  static const _thicknessPresets = [('얇게', 4.0), ('보통', 8.0), ('굵게', 14.0)];

  Widget _completeButton() => KeyedSubtree(
    key: const ValueKey('drawing-complete-button'),
    child: _ToolbarAssetAction(
      key: const ValueKey('drawing-complete'),
      assetPath: 'assets/canvas/frame/button_green.png',
      semanticLabel: isCompleting ? '그림 완료 처리 중' : '그림 완료',
      tooltip: isCompleting ? '완료 처리 중' : '완료',
      onPressed: canComplete && !isCompleting ? onComplete : null,
      isLoading: isCompleting,
      width: 72,
      // 승인 디자인의 문구다. 아이에게는 '완료'보다 해낸 느낌을 준다.
      foreground: const Text(
        '완성!',
        maxLines: 1,
        style: TextStyle(
          color: AppColors.canvasInk,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

final class _ToolbarSaveStatus extends StatelessWidget {
  const _ToolbarSaveStatus({
    required this.status,
    required this.onRetry,
    required this.width,
  });

  final DrawingSaveStatus status;
  final VoidCallback onRetry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      // 툴바 폭이 좁아 긴 문장은 잘린다. 상태는 짧게 적고 자세한 안내는 하지 않는다.
      DrawingSaveStatus.localOnly => ('저장 대기', AppColors.canvasStatusLocalInk),
      DrawingSaveStatus.saving => ('저장 중...', AppColors.canvasStatusSavingInk),
      DrawingSaveStatus.saved => ('저장됨', AppColors.canvasStatusSavedInk),
      DrawingSaveStatus.failed => (
        '저장하지 못했어요',
        AppColors.canvasStatusFailedInk,
      ),
    };
    final failed = status == DrawingSaveStatus.failed;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 28,
          child: status == DrawingSaveStatus.saving
              ? Padding(
                  padding: const EdgeInsets.all(5),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: color,
                  ),
                )
              : Image.asset(
                  'assets/canvas/frame/save.png',
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      key: const ValueKey('drawing-save-status'),
      width: width,
      height: 48,
      child: Tooltip(
        message: failed ? '$label. 다시 시도' : label,
        excludeFromSemantics: true,
        child: Semantics(
          liveRegion: true,
          label: failed ? '$label. 다시 시도' : label,
          button: failed,
          enabled: failed ? true : null,
          onTap: failed ? onRetry : null,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: failed
                ? InkWell(
                    key: const ValueKey('save-retry'),
                    excludeFromSemantics: true,
                    borderRadius: BorderRadius.circular(12),
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: content,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}

final class _ThicknessPresetButton extends StatelessWidget {
  const _ThicknessPresetButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label 굵기',
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          excludeFromSemantics: true,
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.canvasInk,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

DrawingCanvasDeviceClass _deviceClassFor(Size size) {
  if (size.width >= 900 && size.height > 520) {
    return DrawingCanvasDeviceClass.tablet;
  }
  if (size.width >= 640 && size.height <= 520) {
    return DrawingCanvasDeviceClass.mobileLandscape;
  }
  return DrawingCanvasDeviceClass.mobilePortrait;
}

final class _ToolbarChrome extends StatelessWidget {
  const _ToolbarChrome({required this.deviceClass, required this.child});

  final DrawingCanvasDeviceClass deviceClass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tablet = deviceClass == DrawingCanvasDeviceClass.tablet;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Image.asset(
            tablet
                ? 'assets/canvas/frame/toolbar_frame_tablet.png'
                : 'assets/canvas/frame/toolbar_frame_mobile.png',
            fit: BoxFit.fill,
            centerSlice: tablet
                ? const Rect.fromLTRB(28, 22, 1230, 62)
                : const Rect.fromLTRB(28, 18, 802, 44),
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
        child,
      ],
    );
  }
}

final class _QuickColorButton extends StatefulWidget {
  const _QuickColorButton({
    required this.index,
    required this.assetPath,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final int index;
  final String assetPath;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_QuickColorButton> createState() => _QuickColorButtonState();
}

final class _QuickColorButtonState extends State<_QuickColorButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final emphasized = widget.selected || _hovered || _focused;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Tooltip(
      message: '빠른 색상 ${widget.index + 1}',
      excludeFromSemantics: true,
      child: Semantics(
        label: '빠른 색상 ${widget.index + 1}',
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
              child: Center(
                child: AnimatedScale(
                  key: ValueKey('drawing-quick-color-scale-${widget.index}'),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  scale: emphasized ? 1.06 : 1,
                  child: SizedBox.square(
                    dimension: 36,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (widget.selected)
                          CustomPaint(
                            key: ValueKey(
                              'drawing-quick-color-selection-ring-${widget.index}',
                            ),
                            size: const Size.square(36),
                            painter: const _CrayonSelectionRingPainter(),
                          ),
                        SizedBox.square(
                          key: ValueKey(
                            'drawing-quick-color-swatch-${widget.index}',
                          ),
                          dimension: 28,
                          child: Image.asset(
                            widget.assetPath,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _CrayonSelectionRingPainter extends CustomPainter {
  const _CrayonSelectionRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerPaint = Paint()
      ..color = AppColors.canvasInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    final innerPaint = Paint()
      ..color = AppColors.canvasInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-0.35, 0.2),
        width: size.width - 3,
        height: size.height - 3.8,
      ),
      outerPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0.45, -0.3),
        width: size.width - 7.2,
        height: size.height - 6.4,
      ),
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrayonSelectionRingPainter oldDelegate) =>
      false;
}

final class _ToolbarAssetAction extends StatefulWidget {
  const _ToolbarAssetAction({
    required this.assetPath,
    required this.semanticLabel,
    required this.tooltip,
    required this.onPressed,
    this.foreground,
    this.isLoading = false,
    this.width = 48,
    super.key,
  });

  final String assetPath;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget? foreground;
  final bool isLoading;
  final double width;

  @override
  State<_ToolbarAssetAction> createState() => _ToolbarAssetActionState();
}

final class _ToolbarAssetActionState extends State<_ToolbarAssetAction> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final emphasized = enabled && (_hovered || _focused);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        label: widget.semanticLabel,
        button: true,
        enabled: enabled,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: SizedBox(
          width: widget.width,
          height: 48,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              excludeFromSemantics: true,
              canRequestFocus: enabled,
              mouseCursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onHover: (value) {
                if (_hovered != value) setState(() => _hovered = value);
              },
              onFocusChange: (value) {
                if (_focused != value) setState(() => _focused = value);
              },
              onTap: widget.onPressed,
              child: Center(
                child: AnimatedScale(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  scale: emphasized ? 1.06 : 1,
                  child: Opacity(
                    opacity: widget.isLoading || enabled ? 1 : .45,
                    child: SizedBox(
                      width: widget.width - 8,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            widget.assetPath,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                          if (widget.isLoading)
                            const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.canvasInk,
                              ),
                            )
                          else if (widget.foreground != null)
                            widget.foreground!,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
