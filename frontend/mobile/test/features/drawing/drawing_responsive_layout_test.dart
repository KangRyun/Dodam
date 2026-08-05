import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_crayon_frame.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrawingScreen responsive crayon shell', () {
    const cases = <({Size size, String layoutKey, double toolbarHeight})>[
      (
        size: Size(390, 844),
        layoutKey: 'drawing-shell-mobile-portrait',
        toolbarHeight: 128,
      ),
      (
        size: Size(844, 390),
        layoutKey: 'drawing-shell-mobile-landscape',
        toolbarHeight: 68,
      ),
      (
        size: Size(1194, 834),
        layoutKey: 'drawing-shell-tablet',
        toolbarHeight: 84,
      ),
    ];

    for (final testCase in cases) {
      testWidgets(
        '${testCase.size} keeps fixed primary actions and a contained document at 2x text',
        (tester) async {
          await _pumpDrawing(tester, size: testCase.size, textScale: 2);

          expect(tester.takeException(), isNull);
          expect(find.byKey(ValueKey(testCase.layoutKey)), findsOneWidget);
          expect(find.byType(DrawingToolbar), findsOneWidget);
          expect(find.byType(DrawingCrayonFrame), findsOneWidget);
          expect(
            tester
                .getSize(find.byKey(const ValueKey('drawing-toolbar')))
                .height,
            testCase.toolbarHeight,
          );

          for (final key in const [
            'drawing-back',
            'undo-action',
            'redo-action',
            'drawing-tool-crayon',
            'drawing-tool-pencil',
            'drawing-tool-brush',
            'drawing-tool-eraser',
            'drawing-tool-fill',
            'drawing-save-status',
            'drawing-complete',
          ]) {
            expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
          }

          final markerRect = tester.getRect(
            find.byKey(const ValueKey('drawing-document-marker')),
          );
          expect(markerRect.width, greaterThan(0));
          expect(markerRect.height, greaterThan(0));
          expect(markerRect.left, greaterThanOrEqualTo(0));
          expect(markerRect.top, greaterThanOrEqualTo(0));
          expect(markerRect.right, lessThanOrEqualTo(testCase.size.width));
          expect(markerRect.bottom, lessThanOrEqualTo(testCase.size.height));
        },
      );
    }

    testWidgets(
      'tablet startup tolerates a transient zero-width layout constraint',
      (tester) async {
        tester.view.physicalSize = const Size(1194, 834);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 0,
                height: 834,
                child: DrawingScreen(childId: '3'),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'mobile palette is dismissible and does not move the document',
      (tester) async {
        await _pumpDrawing(tester, size: const Size(390, 844));
        final marker = find.byKey(const ValueKey('drawing-document-marker'));
        final before = tester.getRect(marker);

        final paletteButton = find.byKey(
          const ValueKey('drawing-palette-button'),
        );
        await tester.ensureVisible(paletteButton);
        await tester.pumpAndSettle();
        await tester.tap(paletteButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('drawing-mobile-palette-sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('drawing-color-palette')),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<ModalBarrier>(find.byType(ModalBarrier))
              .last
              .dismissible,
          isTrue,
        );
        expect(tester.getRect(marker), before);

        Navigator.of(
          tester.element(
            find.byKey(const ValueKey('drawing-mobile-palette-sheet')),
          ),
        ).pop();
        await tester.pumpAndSettle();
        expect(tester.getRect(marker), before);
      },
    );

    for (final size in const [Size(1194, 834), Size(1600, 900)]) {
      testWidgets(
        'tablet palette at $size stays anchored to its trigger outside capture',
        (tester) async {
          await _pumpDrawing(tester, size: size);
          final marker = find.byKey(const ValueKey('drawing-document-marker'));
          final documentBefore = tester.getRect(marker);

          final paletteButton = find.byKey(
            const ValueKey('drawing-palette-button'),
          );
          await tester.ensureVisible(paletteButton);
          await tester.pumpAndSettle();
          final triggerRect = tester.getRect(paletteButton);
          expect(triggerRect.size, const Size.square(48));
          await tester.tap(paletteButton);
          await tester.pumpAndSettle();

          final popover = find.byKey(
            const ValueKey('drawing-tablet-palette-popover'),
          );
          expect(popover, findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            tester
                .widgetList<ModalBarrier>(find.byType(ModalBarrier))
                .last
                .dismissible,
            isTrue,
          );
          expect(tester.getRect(marker), documentBefore);
          expect(find.ancestor(of: popover, matching: marker), findsNothing);
          expect(
            _horizontalIntervalGap(triggerRect, tester.getRect(popover)),
            lessThanOrEqualTo(16),
          );
        },
      );
    }

    testWidgets(
      'frame, toolbar, cursor, and stage chrome stay outside capture',
      (tester) async {
        await _pumpDrawing(tester, size: const Size(1194, 834));

        final marker = find.byKey(const ValueKey('drawing-document-marker'));
        final markerWidget = tester.widget<KeyedSubtree>(marker);
        expect(markerWidget.child, isA<RepaintBoundary>());
        expect(
          find.ancestor(of: marker, matching: find.byType(DrawingCrayonFrame)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: marker,
            matching: find.byKey(const ValueKey('drawing-toolbar')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: marker,
            matching: find.byKey(
              const ValueKey('drawing-crayon-frame-nine-slice'),
            ),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: marker,
            matching: find.byKey(const ValueKey('drawing-cursor-overlay')),
          ),
          findsNothing,
        );
        expect(find.byType(AiQuestionBubbleOverlay), findsOneWidget);
        expect(
          find.descendant(
            of: marker,
            matching: find.byType(AiQuestionBubbleOverlay),
          ),
          findsNothing,
        );
        // 질문·오류가 없는 동안에는 사이드 패널을 아예 띄우지 않는다. 빈 상자를
        // 캔버스 위에 겹쳐 두면 그 아래 그리기와 복원 안내가 탭을 받지 못한다.
        final stageChrome = find.byKey(const ValueKey('drawing-stage-chrome'));
        expect(stageChrome, findsNothing);
        expect(
          find.descendant(of: marker, matching: stageChrome),
          findsNothing,
        );
      },
    );
  });
}

double _horizontalIntervalGap(Rect first, Rect second) {
  if (first.right < second.left) return second.left - first.right;
  if (second.right < first.left) return first.left - second.right;
  return 0;
}

Future<void> _pumpDrawing(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const DrawingScreen(childId: '3'),
    ),
  );
  await tester.pumpAndSettle();
}
