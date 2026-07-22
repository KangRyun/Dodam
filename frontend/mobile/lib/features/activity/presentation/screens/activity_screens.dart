import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';
import '../../../../design_system/design_system.dart';
import '../../../drawing/presentation/models/drawing_stroke.dart';
import '../../../drawing/presentation/widgets/drawing_canvas.dart';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({required this.childId, this.sessionId, super.key});

  final String childId;
  final int? sessionId;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  static const _thin = 4.0;
  static const _regular = 8.0;
  static const _thick = 14.0;

  final List<DrawingStroke> _completedStrokes = [];
  DrawingStroke? _activeStroke;
  Color _color = AppColors.drawingInk;
  double _thickness = _regular;
  int? _activePointer;

  void _startStroke(PointerDownEvent event) {
    if (_activePointer != null) return;
    setState(() {
      _activePointer = event.pointer;
      _activeStroke = DrawingStroke(
        points: [_pointFrom(event)],
        color: _color,
        thickness: _thickness,
      );
    });
  }

  void _extendStroke(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _activeStroke == null) return;
    setState(() {
      _activeStroke = _activeStroke!.addPoint(_pointFrom(event));
    });
  }

  void _endStroke(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    setState(() {
      final stroke = _activeStroke;
      if (event is PointerUpEvent && stroke != null) {
        _completedStrokes.add(stroke);
      }
      _activeStroke = null;
      _activePointer = null;
    });
  }

  void _undoLastStroke() {
    if (_activeStroke != null || _completedStrokes.isEmpty) return;
    setState(() => _completedStrokes.removeLast());
  }

  DrawingPoint _pointFrom(PointerEvent event) => DrawingPoint(
    position: event.localPosition,
    pressure: event.pressureMin == event.pressureMax ? 1 : event.pressure,
  );

  void _showCompletePlaceholder() {
    showAppMessage(context, message: '그림 완료는 다음 단계에서 연결할게요.');
  }

  List<DrawingStroke> get _visibleStrokes {
    final strokes = [..._completedStrokes];
    if (_activeStroke case final stroke?) strokes.add(stroke);
    return List.unmodifiable(strokes);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.childCanvas,
    appBar: AppTopBar(
      title: '그림 활동',
      onBack: () => Navigator.of(context).pop(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: IconButton.filledTonal(
            key: const ValueKey('undo-action'),
            tooltip: _activeStroke != null
                ? '그리는 중에는 실행 취소할 수 없어요'
                : '마지막 그림 획 실행 취소',
            onPressed: _activeStroke == null && _completedStrokes.isNotEmpty
                ? _undoLastStroke
                : null,
            icon: const Icon(Icons.undo_rounded),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvas = _CanvasPanel(
            strokes: _visibleStrokes,
            onPointerDown: _startStroke,
            onPointerMove: _extendStroke,
            onPointerUp: _endStroke,
          );
          final sidePanel = _DrawingSidePanel(
            selectedColor: _color,
            selectedThickness: _thickness,
            onColorChanged: (color) => setState(() => _color = color),
            onThicknessChanged: (value) => setState(() => _thickness = value),
            canComplete: _activeStroke == null && _completedStrokes.isNotEmpty,
            onComplete: _showCompletePlaceholder,
          );
          if (constraints.maxWidth >= 900) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(flex: 3, child: canvas),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 320, child: sidePanel),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                SizedBox(height: 420, child: canvas),
                const SizedBox(height: AppSpacing.md),
                sidePanel,
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _CanvasPanel extends StatelessWidget {
  const _CanvasPanel({
    required this.strokes,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
  });

  final List<DrawingStroke> strokes;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerEvent> onPointerUp;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outlineStrong, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: DrawingCanvas(
      strokes: strokes,
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerUp: onPointerUp,
    ),
  );
}

class _DrawingSidePanel extends StatelessWidget {
  const _DrawingSidePanel({
    required this.selectedColor,
    required this.selectedThickness,
    required this.onColorChanged,
    required this.onThicknessChanged,
    required this.canComplete,
    required this.onComplete,
  });

  final Color selectedColor;
  final double selectedThickness;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onThicknessChanged;
  final bool canComplete;
  final VoidCallback onComplete;

  static const _colors = <(String, Color)>[
    ('검정', AppColors.drawingInk),
    ('빨강', AppColors.drawingRed),
    ('파랑', AppColors.drawingBlue),
    ('노랑', AppColors.drawingYellow),
  ];
  static const _thicknesses = <(String, double)>[
    ('얇게', _DrawingScreenState._thin),
    ('보통', _DrawingScreenState._regular),
    ('굵게', _DrawingScreenState._thick),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.tangerineSoft,
              child: Icon(
                Icons.emoji_nature_rounded,
                color: AppColors.tangerine,
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '자유롭게 그려 보자!',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ToolHeading(icon: Icons.edit_rounded, label: '펜'),
        const SizedBox(height: AppSpacing.xs),
        const _SelectedToolCard(),
        const SizedBox(height: AppSpacing.lg),
        const _ToolHeading(icon: Icons.palette_outlined, label: '색상'),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (name, color) in _colors)
              _ColorChoice(
                name: name,
                color: color,
                selected: selectedColor == color,
                onTap: () => onColorChanged(color),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ToolHeading(icon: Icons.line_weight_rounded, label: '굵기'),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<double>(
          segments: [
            for (final (label, value) in _thicknesses)
              ButtonSegment(value: value, label: Text(label)),
          ],
          selected: {selectedThickness},
          showSelectedIcon: true,
          onSelectionChanged: (values) => onThicknessChanged(values.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.lavenderSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Text(
            '대화와 마이크는 다음 단계에서 만나요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 16),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const ValueKey('drawing-complete'),
          label: '다 그렸어요!',
          variant: AppButtonVariant.child,
          onPressed: canComplete ? onComplete : null,
        ),
      ],
    ),
  );
}

class _ToolHeading extends StatelessWidget {
  const _ToolHeading({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppColors.inkMuted, size: 20),
      const SizedBox(width: AppSpacing.xs),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _SelectedToolCard extends StatelessWidget {
  const _SelectedToolCard();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.leafSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.leaf, width: 2),
    ),
    child: const Row(
      children: [
        Icon(Icons.edit_rounded, color: AppColors.leaf),
        SizedBox(width: AppSpacing.xs),
        Text('기본 펜 선택됨', style: TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$name 색상',
    selected: selected,
    button: true,
    child: InkWell(
      key: ValueKey('color-$name'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.leaf : AppColors.outline,
            width: selected ? 4 : 2,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                color: color.computeLuminance() > 0.55
                    ? AppColors.ink
                    : Colors.white,
              )
            : null,
      ),
    ),
  );
}

class EmotionSelectScreen extends StatelessWidget {
  const EmotionSelectScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '감정 선택',
    description: '그림을 그리며 느낀 감정을 고르는 화면이에요.',
    childFriendly: true,
    primaryLabel: '선택 완료',
    onPrimary: () => Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.activityComplete(childId)),
  );
}

class ActivityCompleteScreen extends StatelessWidget {
  const ActivityCompleteScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 완료',
    description: '참 잘했어요. 이제 보호자에게 태블릿을 전달해 주세요.',
    childFriendly: true,
    canPop: false,
  );
}
