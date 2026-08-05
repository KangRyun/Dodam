import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

import '../../application/drawing_sync_coordinator.dart';
import '../models/drawing_tool_state.dart';
import '../rendering/drawing_stroke_renderer.dart';
import 'canvas_tool_asset_icon.dart';
import 'canvas_tutorial_target_registry.dart';
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
    required this.saveStatus,
    required this.onUndo,
    required this.onRedo,
    required this.onRetrySave,
    required this.onInstrumentChanged,
    required this.onEraserMenuAction,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpenPalette,
    this.pencilOnly = false,
    this.tutorialTargets,
    super.key,
  });

  final DrawingToolState toolState;
  final List<Color> quickColors;
  final LayerLink paletteAnchorLink;
  final VoidCallback onBack;
  final bool canUndo;
  final bool canRedo;
  final DrawingSaveStatus saveStatus;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onRetrySave;
  final ValueChanged<DrawingInstrument> onInstrumentChanged;
  final ValueChanged<DrawingEraserMenuAction> onEraserMenuAction;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final VoidCallback onOpenPalette;
  final bool pencilOnly;

  /// 도구 안내가 가리킬 자리를 심어 둘 곳이다. 배치와 모양은 바뀌지 않는다.
  final CanvasTutorialTargetRegistry? tutorialTargets;

  /// 안내가 이 위젯의 화면 위 위치를 읽을 수 있게 key 만 덧씌운다.
  Widget _tutorialTarget(CanvasTutorialTargetId id, String slot, Widget child) {
    final registry = tutorialTargets;
    if (registry == null) return child;
    return KeyedSubtree(key: registry.key(id, slot), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final deviceClass = _deviceClassFor(MediaQuery.sizeOf(context));
    final primaryActions = _primaryActions(context);

    return switch (deviceClass) {
      DrawingCanvasDeviceClass.mobilePortrait => SizedBox(
        key: const ValueKey('drawing-toolbar'),
        height: 128,
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: _ToolbarChrome(
                deviceClass: deviceClass,
                // 좁은 화면에서는 도구가 한 줄에 다 안 들어간다. 넘치면 잘리는
                // 대신 옆으로 밀어 볼 수 있게 한다.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: const ValueKey('drawing-toolbar-primary-row'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: primaryActions.take(7).toList(growable: false),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 64,
              child: _ToolbarChrome(
                deviceClass: deviceClass,
                child: Row(
                  children: [
                    ...primaryActions.skip(7),
                    Expanded(child: _secondaryControls()),
                    _ToolbarSaveStatus(
                      status: saveStatus,
                      onRetry: onRetrySave,
                      width: 112,
                    ),
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
        height: 68,
      ),
      DrawingCanvasDeviceClass.tablet => _singleRow(
        context,
        deviceClass: deviceClass,
        height: 84,
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
        ],
      ),
    ),
  );

  List<Widget> _primaryActions(BuildContext context) {
    final actions = <Widget>[
      _ToolbarAssetAction(
        key: const ValueKey('drawing-back'),
        assetPath: 'assets/canvas/frame/back.png',
        semanticLabel: '뒤로 가기',
        tooltip: '뒤로 가기',
        onPressed: onBack,
      ),
      _tutorialTarget(
        CanvasTutorialTargetId.history,
        'undo',
        _ToolbarAssetAction(
          key: const ValueKey('undo-action'),
          assetPath: 'assets/canvas/frame/undo.png',
          semanticLabel: '실행 취소',
          tooltip: '실행 취소',
          onPressed: canUndo ? onUndo : null,
        ),
      ),
      _tutorialTarget(
        CanvasTutorialTargetId.history,
        'redo',
        _ToolbarAssetAction(
          key: const ValueKey('redo-action'),
          assetPath: 'assets/canvas/frame/redo.png',
          semanticLabel: '다시 실행',
          tooltip: '다시 실행',
          onPressed: canRedo ? onRedo : null,
        ),
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
      _tutorialTarget(
        CanvasTutorialTargetId.eraser,
        'main',
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
      ),
      _instrumentButton(
        instrument: DrawingInstrument.fill,
        artwork: CanvasToolArtwork.fill,
        label: '채우기',
      ),
      _paletteButton(),
    ];
    if (!pencilOnly) return actions;
    return [actions[0], actions[1], actions[2], actions[4], actions[6]];
  }

  Widget _instrumentButton({
    required DrawingInstrument instrument,
    required CanvasToolArtwork artwork,
    required String label,
  }) {
    final Widget button = DrawingToolButton(
      key: ValueKey('drawing-tool-${instrument.name}'),
      artwork: artwork,
      pointColor: toolState.color,
      selected: toolState.instrument == instrument,
      semanticLabel: '$label 도구',
      tooltip: label,
      onPressed: () => onInstrumentChanged(instrument),
    );
    // 그리기 도구 안내는 지우개를 뺀 그리기·칠하기 도구를 함께 가리킨다.
    final target = _tutorialTarget(
      CanvasTutorialTargetId.tools,
      instrument.name,
      button,
    );
    if (instrument != DrawingInstrument.crayon) return target;
    return KeyedSubtree(key: const ValueKey('drawing-tool-pen'), child: target);
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
        if (!pencilOnly) ...[
          _tutorialTarget(
            CanvasTutorialTargetId.colors,
            'quick',
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
          ),
          const SizedBox(width: 8),
        ],
        _tutorialTarget(
          CanvasTutorialTargetId.thickness,
          'slider',
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
        ),
        const SizedBox(width: 8),
        // 슬라이더를 움직이면 이 원이 같이 커진다. 얇게·보통·굵게 같은 글자
        // 단계보다 아이가 굵기를 바로 알아본다. 캔버스 커서와 같은 계산을 써서
        // 여기 보이는 크기가 실제로 찍히는 자국 크기와 같다.
        _tutorialTarget(
          CanvasTutorialTargetId.thickness,
          'preview',
          SizedBox.square(
            key: const ValueKey('drawing-thickness-preview'),
            dimension: 48,
            child: Center(
              // 굵기 점만 두면 얇을 때 먼지처럼 보인다. 크기가 변하지 않는 자리를
              // 두고 그 안에서 점이 커지게 해야 어느 정도인지 견줄 수 있다.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // 툴바보다 밝으면 자리 자체가 튀어 보인다. 종이 톤으로 낮춘다.
                  color: AppColors.canvasStage,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.canvasBorder),
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: toolState.color,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: DrawingStrokeRenderer.footprintFor(
                          toolState.brushProfile,
                          toolState.width,
                        ).clamp(3, 32),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  /// 팔레트는 색을 고르는 버튼이라 도구 줄 끝, 색 견본 바로 앞에 둔다.
  Widget _paletteButton() => _tutorialTarget(
    CanvasTutorialTargetId.colors,
    'palette',
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
        // 테두리 원화 안쪽은 비어 있다. 여기에 면을 깔지 않으면 바깥 배경이
        // 그대로 비쳐 툴바가 배경과 한 덩어리로 보인다.
        Padding(
          padding: const EdgeInsets.all(_toolbarBorderInset),
          child: DecoratedBox(
            key: const ValueKey('drawing-toolbar-surface'),
            decoration: BoxDecoration(
              color: AppColors.canvasToolbarSurface,
              borderRadius: BorderRadius.circular(tablet ? 14 : 10),
            ),
          ),
        ),
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
        // 테두리가 둥글게 말리는 만큼 안쪽으로 들여야 첫 버튼과 완성 버튼이
        // 모서리 선을 타고 넘어가 보이지 않는다(시안도 좌우 14px 를 비운다).
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tablet ? 14 : 10),
          child: child,
        ),
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
                            size: const Size.square(42),
                            painter: const _CrayonSelectionRingPainter(),
                          ),
                        SizedBox.square(
                          key: ValueKey(
                            'drawing-quick-color-swatch-${widget.index}',
                          ),
                          dimension: 34,
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
    // 검은 견본 위에서도 링이 견본과 붙어 덩어리로 보이지 않도록, 밝은 띠를
    // 안쪽에 한 겹 두고 그 바깥에 잉크 선을 한 줄만 그린다.
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width - 6,
          height: size.height - 6,
        ),
        Paint()
          ..color = AppColors.canvasWarm
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      )
      ..drawOval(
        Rect.fromCenter(
          center: center.translate(-0.3, 0.2),
          width: size.width - 3,
          height: size.height - 3.6,
        ),
        Paint()
          ..color = AppColors.canvasInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
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
    super.key,
  });

  final String assetPath;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback? onPressed;

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
          width: 48,
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
                    opacity: enabled ? 1 : .45,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Image.asset(
                        widget.assetPath,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
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

/// 툴바 테두리 선이 원화 가장자리에서 안쪽으로 들어간 만큼이다. 면을 이만큼
/// 비워야 색이 선 밖으로 새지 않는다.
const double _toolbarBorderInset = 5;
