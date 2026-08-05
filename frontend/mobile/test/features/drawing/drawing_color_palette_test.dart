import 'dart:ui';

import 'package:dodam/features/drawing/presentation/widgets/drawing_color_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const initial = HSVColor.fromAHSV(1, 35, .2, .8);
  const previous = Color(0xFF4D82D8);

  testWidgets(
    'renders distinct HSV plane and hue bar with adjacent current and previous colors',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPalette(tester, initial: initial, previous: previous);

      final plane = find.byKey(const ValueKey('hsv-saturation-value-plane'));
      final hue = find.byKey(const ValueKey('hsv-hue-slider'));
      final current = find.byKey(const ValueKey('drawing-color-current'));
      final previousFinder = find.byKey(
        const ValueKey('drawing-color-previous'),
      );

      expect(plane, findsOneWidget);
      expect(hue, findsOneWidget);
      expect(
        tester.getSize(plane).width,
        greaterThan(tester.getSize(hue).width),
      );
      expect(
        tester.getSize(hue).height,
        greaterThan(tester.getSize(hue).width),
      );
      expect(tester.getRect(plane).overlaps(tester.getRect(hue)), isFalse);
      expect(tester.getRect(current).top, tester.getRect(previousFinder).top);
      expect(
        tester.getRect(current).right,
        lessThanOrEqualTo(tester.getRect(previousFinder).left),
      );

      expect(
        find.byKey(const ValueKey('hsv-selection-cursor-outer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('hsv-selection-cursor-inner')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('현재 색상'), findsOneWidget);
      expect(find.bySemanticsLabel('이전 색상'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('RGB'), findsNothing);
      expect(find.textContaining('저장된 색상'), findsNothing);

      semantics.dispose();
    },
  );

  testWidgets('hue control exposes at least a 48 by 48 hit target', (
    tester,
  ) async {
    await _pumpPalette(tester, initial: initial, previous: previous);

    final size = tester.getSize(find.byKey(const ValueKey('hsv-hue-slider')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('current and previous swatches have visible Korean role labels', (
    tester,
  ) async {
    await _pumpPalette(tester, initial: initial, previous: previous);

    expect(find.text('현재'), findsOneWidget);
    expect(find.text('이전'), findsOneWidget);
  });

  testWidgets('plane and hue gestures emit HSV updates immediately', (
    tester,
  ) async {
    final changes = <HSVColor>[];
    await _pumpPalette(
      tester,
      initial: initial,
      previous: previous,
      onChanged: changes.add,
    );

    final planeRect = tester.getRect(
      find.byKey(const ValueKey('hsv-saturation-value-plane')),
    );
    await tester.tapAt(
      Offset(
        planeRect.left + planeRect.width * .8,
        planeRect.top + planeRect.height * .6,
      ),
    );
    await tester.pump();

    expect(changes, isNotEmpty);
    expect(changes.last, isNot(initial));
    expect(changes.last.hue, closeTo(initial.hue, .01));
    expect(changes.last.saturation, closeTo(.8, .03));
    expect(changes.last.value, closeTo(.4, .03));

    final hueRect = tester.getRect(
      find.byKey(const ValueKey('hsv-hue-slider')),
    );
    await tester.tapAt(
      Offset(hueRect.center.dx, hueRect.top + hueRect.height * .75),
    );
    await tester.pump();

    expect(changes.last.hue, closeTo(270, 4));
    expect(changes.last.saturation, closeTo(.8, .03));
    expect(changes.last.value, closeTo(.4, .03));
  });

  testWidgets('exposes separate cancel and confirm actions', (tester) async {
    var cancelled = 0;
    var confirmed = 0;
    await _pumpPalette(
      tester,
      initial: initial,
      previous: previous,
      onCancel: () => cancelled++,
      onConfirm: () => confirmed++,
    );

    await tester.tap(find.byKey(const ValueKey('drawing-color-cancel')));
    await tester.pump();
    expect(cancelled, 1);
    expect(confirmed, 0);

    await tester.tap(find.byKey(const ValueKey('drawing-color-confirm')));
    await tester.pump();
    expect(cancelled, 1);
    expect(confirmed, 1);
  });

  testWidgets('HSV controls support semantics and directional keyboard input', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <HSVColor>[];
    await _pumpPalette(
      tester,
      initial: initial,
      previous: previous,
      onChanged: changes.add,
    );

    final plane = find.byKey(const ValueKey('hsv-saturation-value-plane'));
    final planeData = tester.getSemantics(plane).getSemanticsData();
    expect(planeData.hasAction(SemanticsAction.increase), isTrue);
    expect(planeData.hasAction(SemanticsAction.decrease), isTrue);

    await tester.tap(plane);
    await tester.pump();
    final afterTap = changes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(changes.length, greaterThan(afterTap));

    final hue = find.byKey(const ValueKey('hsv-hue-slider'));
    final hueData = tester.getSemantics(hue).getSemanticsData();
    expect(hueData.hasAction(SemanticsAction.increase), isTrue);
    expect(hueData.hasAction(SemanticsAction.decrease), isTrue);

    await tester.tap(hue);
    await tester.pump();
    final afterHueTap = changes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(changes.length, greaterThan(afterHueTap));

    semantics.dispose();
  });

  testWidgets('recent colour tap updates only the draft preview', (
    tester,
  ) async {
    final recent = List<Color>.generate(
      12,
      (index) => Color(0xFF100000 + index * 0x000A0A),
    );
    final changes = <HSVColor>[];
    await _pumpPalette(
      tester,
      initial: initial,
      previous: previous,
      recentColors: recent,
      onChanged: changes.add,
    );

    expect(find.byKey(const ValueKey('drawing-recent-colors')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('drawing-recent-colors')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('drawing-recent-color-9')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('drawing-recent-color-10')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drawing-recent-color-9')));
    await tester.pump();
    expect(changes.last.toColor().toARGB32(), recent[9].toARGB32());
    expect(
      tester
          .widget<DrawingColorPalette>(find.byType(DrawingColorPalette))
          .value
          .toColor()
          .toARGB32(),
      recent[9].toARGB32(),
    );
  });

  testWidgets('palette body fits compact bottom sheets and anchored popovers', (
    tester,
  ) async {
    for (final width in <double>[336, 480]) {
      await _pumpPalette(
        tester,
        initial: initial,
        previous: previous,
        hostWidth: width,
      );
      expect(tester.takeException(), isNull, reason: 'host width $width');
      expect(
        tester
            .getSize(find.byKey(const ValueKey('drawing-color-palette')))
            .width,
        width,
      );
    }
  });
}

Future<void> _pumpPalette(
  WidgetTester tester, {
  required HSVColor initial,
  required Color previous,
  double hostWidth = 360,
  List<Color> recentColors = const [],
  ValueChanged<HSVColor>? onChanged,
  VoidCallback? onCancel,
  VoidCallback? onConfirm,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: hostWidth,
            child: _PaletteHarness(
              initial: initial,
              previous: previous,
              recentColors: recentColors,
              onChanged: onChanged,
              onCancel: onCancel,
              onConfirm: onConfirm,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _PaletteHarness extends StatefulWidget {
  const _PaletteHarness({
    required this.initial,
    required this.previous,
    this.recentColors = const [],
    this.onChanged,
    this.onCancel,
    this.onConfirm,
  });

  final HSVColor initial;
  final Color previous;
  final List<Color> recentColors;
  final ValueChanged<HSVColor>? onChanged;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  State<_PaletteHarness> createState() => _PaletteHarnessState();
}

final class _PaletteHarnessState extends State<_PaletteHarness> {
  late HSVColor value = widget.initial;

  @override
  Widget build(BuildContext context) => DrawingColorPalette(
    value: value,
    previousColor: widget.previous,
    recentColors: widget.recentColors,
    onCancel: widget.onCancel ?? () {},
    onConfirm: widget.onConfirm ?? () {},
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => value = next);
    },
  );
}
