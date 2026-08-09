import 'dart:ui';

import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_tool_state.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_asset_icon.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_crayon_frame.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_tool_button.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const quickColors = <Color>[
    AppColors.drawingRed,
    Color(0xFFF47A28),
    AppColors.drawingYellow,
    AppColors.drawingGreen,
    Color(0xFF2E9F98),
    AppColors.drawingBlue,
    AppColors.drawingPurple,
    AppColors.canvasInk,
  ];

  group('DrawingToolbar accessibility', () {
    testWidgets(
      'pencil-only mode keeps eraser and thickness but hides colour tools',
      (tester) async {
        await _pumpToolbar(tester, quickColors: quickColors, pencilOnly: true);

        expect(
          find.byKey(const ValueKey('drawing-tool-pencil')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('drawing-tool-eraser')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('drawing-thickness-slider')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('drawing-tool-crayon')), findsNothing);
        expect(find.byKey(const ValueKey('drawing-tool-brush')), findsNothing);
        expect(find.byKey(const ValueKey('drawing-tool-fill')), findsNothing);
        expect(
          find.byKey(const ValueKey('drawing-palette-button')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('drawing-quick-colors')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'keeps every primary action at 48px and renders tools with approved artwork',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpToolbar(tester, quickColors: quickColors);

        const actionKeys = <String>[
          'drawing-back',
          'undo-action',
          'redo-action',
          'drawing-tool-crayon',
          'drawing-tool-pencil',
          'drawing-tool-brush',
          'drawing-tool-eraser',
          'drawing-tool-fill',
          'drawing-palette-button',
          'drawing-save-status',
        ];
        for (final key in actionKeys) {
          final size = tester.getSize(find.byKey(ValueKey(key)));
          expect(size.width, greaterThanOrEqualTo(48), reason: key);
          expect(size.height, greaterThanOrEqualTo(48), reason: key);
        }

        const artworkByKey = <String, CanvasToolArtwork>{
          'drawing-tool-crayon': CanvasToolArtwork.crayon,
          'drawing-tool-pencil': CanvasToolArtwork.pencil,
          'drawing-tool-brush': CanvasToolArtwork.brush,
          'drawing-tool-eraser': CanvasToolArtwork.eraser,
          'drawing-tool-fill': CanvasToolArtwork.fill,
          'drawing-palette-button': CanvasToolArtwork.palette,
        };
        for (final entry in artworkByKey.entries) {
          final artwork = tester.widget<CanvasToolAssetIcon>(
            find.descendant(
              of: find.byKey(ValueKey(entry.key)),
              matching: find.byType(CanvasToolAssetIcon),
            ),
          );
          expect(artwork.artwork, entry.value);
          expect(artwork.pointColor, AppColors.canvasInk);
          expect(
            find.descendant(
              of: find.byKey(ValueKey(entry.key)),
              matching: find.byType(Icon),
            ),
            findsNothing,
          );
        }

        final crayonSemantics = tester.getSemantics(
          find.bySemanticsLabel('크레용 도구'),
        );
        expect(crayonSemantics.flagsCollection.isButton, isTrue);
        expect(crayonSemantics.flagsCollection.isSelected, Tristate.isTrue);
        expect(find.textContaining('highlighter'), findsNothing);
        expect(find.textContaining('형광펜'), findsNothing);

        semantics.dispose();
      },
    );

    testWidgets(
      'renders all textured quick colors and selects charcoal initially',
      (tester) async {
        await _pumpToolbar(tester, quickColors: quickColors);

        // 팔레트는 색을 고르는 버튼이라 도구 줄 끝, 색 견본 앞에 둔다
        // (S15P11B209-807).
        final ordered = <Finder>[
          find.byKey(const ValueKey('drawing-palette-button')),
          find.byKey(const ValueKey('drawing-quick-colors')),
          find.byKey(const ValueKey('drawing-thickness-slider')),
          find.byKey(const ValueKey('drawing-thickness-preview')),
        ];
        for (var index = 0; index < ordered.length - 1; index++) {
          final current = tester.getRect(ordered[index]);
          final next = tester.getRect(ordered[index + 1]);
          expect(current.right, lessThanOrEqualTo(next.left));
          expect(current.overlaps(next), isFalse);
        }

        final baseSizes = <Size>[];
        for (var index = 0; index < quickColors.length; index++) {
          final target = find.byKey(ValueKey('drawing-quick-color-$index'));
          expect(tester.getSize(target), const Size(48, 48));
          baseSizes.add(
            tester.getSize(
              find.byKey(ValueKey('drawing-quick-color-swatch-$index')),
            ),
          );
        }
        // 견본이 상자 안에서 도구 그림과 같은 비율로 차야 툴바 리듬이 맞는다.
        expect(baseSizes.toSet(), {const Size(34, 34)});

        const expectedSwatchAssets = <String>[
          'assets/canvas/swatches/red.png',
          'assets/canvas/swatches/orange.png',
          'assets/canvas/swatches/yellow.png',
          'assets/canvas/swatches/green.png',
          'assets/canvas/swatches/teal.png',
          'assets/canvas/swatches/blue.png',
          'assets/canvas/swatches/purple.png',
          'assets/canvas/swatches/charcoal.png',
        ];
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('drawing-quick-colors')),
            matching: find.byType(Image),
          ),
          findsNWidgets(expectedSwatchAssets.length),
        );
        for (var index = 0; index < expectedSwatchAssets.length; index++) {
          final image = tester.widget<Image>(
            find.descendant(
              of: find.byKey(ValueKey('drawing-quick-color-swatch-$index')),
              matching: find.byType(Image),
            ),
          );
          expect(
            (image.image as AssetImage).assetName,
            expectedSwatchAssets[index],
          );
        }

        final selectedScale = tester.widget<AnimatedScale>(
          find.byKey(const ValueKey('drawing-quick-color-scale-7')),
        );
        final unselectedScale = tester.widget<AnimatedScale>(
          find.byKey(const ValueKey('drawing-quick-color-scale-0')),
        );
        expect(selectedScale.scale, greaterThan(1));
        expect(unselectedScale.scale, 1);
        expect(
          find.byKey(const ValueKey('drawing-quick-color-selection-ring-7')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('drawing-quick-color-selection-ring-0')),
          findsNothing,
        );

        final selectedSemantics = tester.getSemantics(
          find.bySemanticsLabel('빠른 색상 8'),
        );
        expect(selectedSemantics.flagsCollection.isSelected, Tristate.isTrue);
        // 굵기 미리보기 원은 다른 툴바 버튼과 같은 상자를 쓴다.
        expect(tester.getSize(ordered[3]), const Size(48, 48));
      },
    );

    testWidgets(
      'keeps save and thickness labels readable without scaling text down',
      (tester) async {
        const expectedStatusInks = <DrawingSaveStatus, Color>{
          DrawingSaveStatus.localOnly: AppColors.canvasStatusLocalInk,
          DrawingSaveStatus.saving: Color(0xFF655194),
          DrawingSaveStatus.saved: Color(0xFF3D7A55),
          DrawingSaveStatus.failed: Color(0xFFB33A3A),
        };

        for (final entry in expectedStatusInks.entries) {
          await _pumpToolbar(
            tester,
            quickColors: quickColors,
            saveStatus: entry.key,
          );

          final status = find.byKey(const ValueKey('drawing-save-status'));
          final text = tester.widget<Text>(
            find.descendant(of: status, matching: find.byType(Text)),
          );
          expect(text.style?.fontSize, greaterThanOrEqualTo(13));
          expect(
            text.style!.fontWeight!.value,
            lessThanOrEqualTo(FontWeight.w800.value),
          );
          expect(text.style?.color, entry.value);
          expect(
            _contrastRatio(entry.value, AppColors.canvasToolbarSurface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            find.descendant(of: status, matching: find.byType(FittedBox)),
            findsNothing,
          );
        }

        // 굵기는 글자 단계가 아니라 슬라이더와 원으로 보여 준다
        // (S15P11B209-807). 원은 굵기를 올리면 같이 커져야 한다.
        double previewDiameter() => tester
            .getSize(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('drawing-thickness-preview')),
                    matching: find.byType(SizedBox),
                  )
                  .last,
            )
            .width;

        await _pumpToolbar(tester, quickColors: quickColors, width: 4);
        final thin = previewDiameter();
        await _pumpToolbar(tester, quickColors: quickColors, width: 24);
        expect(previewDiameter(), greaterThan(thin));
      },
    );

    testWidgets('disables toolbar scale motion when animations are disabled', (
      tester,
    ) async {
      await _pumpToolbar(
        tester,
        quickColors: quickColors,
        disableAnimations: true,
      );

      final scales = tester.widgetList<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(scales, isNotEmpty);
      for (final scale in scales) {
        expect(scale.duration, Duration.zero);
      }
    });

    testWidgets(
      'hover scales only inner tool artwork while its hit rectangle stays fixed',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: DrawingToolButton(
                  key: const ValueKey('test-tool'),
                  artwork: CanvasToolArtwork.crayon,
                  pointColor: AppColors.canvasInk,
                  selected: false,
                  semanticLabel: '크레용 도구',
                  tooltip: '크레용',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        final target = find.byKey(const ValueKey('test-tool'));
        final before = tester.getRect(target);
        expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, '크레용');
        expect(
          tester
              .widget<AnimatedScale>(
                find.byKey(const ValueKey('drawing-tool-artwork-crayon')),
              )
              .scale,
          1,
        );

        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.addPointer(location: const Offset(1, 1)),
        );
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(target)),
        );
        await tester.pump();

        expect(tester.getRect(target), before);
        expect(
          tester
              .widget<AnimatedScale>(
                find.byKey(const ValueKey('drawing-tool-artwork-crayon')),
              )
              .scale,
          1.06,
        );
      },
    );

    testWidgets(
      'one keyboard focus stop both emphasizes and activates a tool',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: DrawingToolButton(
                  artwork: CanvasToolArtwork.crayon,
                  pointColor: AppColors.canvasInk,
                  selected: false,
                  semanticLabel: '크레용 도구',
                  tooltip: '크레용',
                  onPressed: () => presses++,
                ),
              ),
            ),
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester
              .widget<AnimatedScale>(
                find.byKey(const ValueKey('drawing-tool-artwork-crayon')),
              )
              .scale,
          1.06,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 1);
      },
    );

    testWidgets(
      'semantic taps activate tool, quick color, undo, and back exactly once',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final instruments = <DrawingInstrument>[];
        final colors = <Color>[];
        var undoCount = 0;
        var backCount = 0;
        await _pumpToolbar(
          tester,
          quickColors: quickColors,
          onUndo: () => undoCount++,
          onBack: () => backCount++,
          onInstrumentChanged: instruments.add,
          onColorChanged: colors.add,
        );

        for (final label in <String>['뒤로 가기', '연필 도구', '빠른 색상 2', '실행 취소']) {
          final target = find.semantics.byLabel(label);
          expect(target, findsOne, reason: label);
          expect(target, isSemantics(hasTapAction: true), reason: label);
          tester.semantics.tap(target);
          await tester.pump();
        }

        expect(instruments, [DrawingInstrument.pencil]);
        expect(colors, [quickColors[1]]);
        expect(undoCount, 1);
        expect(backCount, 1);
        semantics.dispose();
      },
    );

    testWidgets('eraser menu exposes only stroke, area, and clear callbacks', (
      tester,
    ) async {
      final actions = <DrawingEraserMenuAction>[];
      await _pumpToolbar(
        tester,
        quickColors: quickColors,
        onEraserMenuAction: actions.add,
      );

      await tester.tap(find.byKey(const ValueKey('drawing-tool-eraser')));
      await tester.pumpAndSettle();

      expect(
        find.byType(PopupMenuItem<DrawingEraserMenuAction>),
        findsNWidgets(3),
      );
      expect(find.text('선 지우개'), findsOneWidget);
      expect(find.text('영역 지우개'), findsOneWidget);
      expect(find.text('전체 지우기'), findsOneWidget);

      await tester.tap(find.text('전체 지우기'));
      await tester.pumpAndSettle();
      expect(actions, [DrawingEraserMenuAction.clearAll]);
    });

    testWidgets('failed save status exposes one fixed retry action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var retries = 0;
      await _pumpToolbar(
        tester,
        quickColors: quickColors,
        saveStatus: DrawingSaveStatus.failed,
        onRetrySave: () => retries++,
      );

      final status = find.byKey(const ValueKey('drawing-save-status'));
      final retry = find.byKey(const ValueKey('save-retry'));
      expect(status, findsOneWidget);
      expect(retry, findsOneWidget);
      expect(tester.getSize(status).height, greaterThanOrEqualTo(48));
      expect(find.text('저장하지 못했어요'), findsOneWidget);
      expect(find.semantics.byLabel('저장하지 못했어요. 다시 시도'), findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      expect(retries, 1);
      semantics.dispose();
    });

    testWidgets('fits its three component layouts and keeps completion fixed', (
      tester,
    ) async {
      const cases = <(Size, double)>[
        (Size(390, 844), 128),
        (Size(844, 390), 68),
        (Size(1194, 834), 84),
      ];

      for (final (size, expectedHeight) in cases) {
        await _pumpToolbar(
          tester,
          quickColors: quickColors,
          size: size,
          textScale: 2,
        );

        expect(tester.takeException(), isNull, reason: '$size');
        expect(
          tester.getSize(find.byKey(const ValueKey('drawing-toolbar'))).height,
          expectedHeight,
          reason: '$size',
        );
        for (final instrument in DrawingInstrument.values) {
          expect(
            find.byKey(ValueKey('drawing-tool-${instrument.name}')),
            findsOneWidget,
          );
        }
      }
    });
  });

  testWidgets(
    'DrawingCrayonFrame draws its own crayon border over a white document',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 320,
              child: DrawingCrayonFrame(
                deviceClass: DrawingCanvasDeviceClass.mobilePortrait,
                child: ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
        ),
      );

      final exterior = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('drawing-crayon-frame-exterior')),
      );
      final document = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('drawing-crayon-document')),
      );
      final spiralOverlay = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('drawing-crayon-frame-spirals')),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );

      // 테두리 밖은 화면 배경이 그대로 보여야 한다.
      expect(exterior.color, Colors.transparent);
      expect(document.color, Colors.white);
      // 테두리는 그림 파일을 늘여 붙이지 않고 직접 그린다(S15P11B209-806).
      // 파일을 늘이면 종이 모서리가 선 밖으로 삐져나오는 자리가 생긴다.
      expect(
        find.byKey(const ValueKey('drawing-crayon-frame-border')),
        findsOneWidget,
      );
      expect(spiralOverlay.ignoring, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('drawing-crayon-frame-exterior')),
          matching: find.byKey(const ValueKey('drawing-crayon-frame-spirals')),
        ),
        findsWidgets,
      );
    },
  );
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required List<Color> quickColors,
  Size size = const Size(1194, 834),
  double textScale = 1,
  bool disableAnimations = false,
  ValueChanged<DrawingEraserMenuAction>? onEraserMenuAction,
  VoidCallback? onBack,
  VoidCallback? onUndo,
  ValueChanged<DrawingInstrument>? onInstrumentChanged,
  ValueChanged<Color>? onColorChanged,
  DrawingSaveStatus saveStatus = DrawingSaveStatus.localOnly,
  VoidCallback? onRetrySave,
  double width = 8,
  bool pencilOnly = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: DrawingToolbar(
            pencilOnly: pencilOnly,
            toolState: DrawingToolState(width: width),
            quickColors: quickColors,
            paletteAnchorLink: LayerLink(),
            onBack: onBack ?? () {},
            canUndo: true,
            canRedo: true,
            saveStatus: saveStatus,
            onUndo: onUndo ?? () {},
            onRedo: () {},
            onRetrySave: onRetrySave ?? () {},
            onInstrumentChanged: onInstrumentChanged ?? (_) {},
            onEraserMenuAction: onEraserMenuAction ?? (_) {},
            onColorChanged: onColorChanged ?? (_) {},
            onWidthChanged: (_) {},
            onOpenPalette: () {},
          ),
        ),
      ),
    ),
  );
  if (saveStatus == DrawingSaveStatus.saving) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}
