import 'dart:ui' show PointerDeviceKind;

import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_document_controller.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_tool_state.dart';
import 'package:dodam/features/drawing/presentation/rendering/drawing_stroke_renderer.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas_viewport.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_cursor_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrawingCanvasViewport', () {
    for (final hostSize in const [
      Size(390, 844),
      Size(844, 390),
      Size(1194, 834),
    ]) {
      // 종이 전체가 그릴 수 있는 자리다(S15P11B209-801). 문서를 고정 크기로
      // 두면 남는 가장자리가 칠해지지 않는 흰 자리로 남는다.
      testWidgets('fills the whole $hostSize host with the document', (
        tester,
      ) async {
        final boundaryKey = GlobalKey();
        late DrawingViewportMetrics metrics;
        await _setHostSize(tester, hostSize);
        await tester.pumpWidget(
          MaterialApp(
            home: DrawingCanvasViewport(
              repaintBoundaryKey: boundaryKey,
              canvas: const ColoredBox(color: Colors.white),
              overlayBuilder: (context, value) {
                metrics = value;
                return const SizedBox.expand();
              },
            ),
          ),
        );
        await tester.pump();

        final marker = find.byKey(const ValueKey('drawing-document-marker'));
        expect(marker, findsOneWidget);
        final markerWidget = tester.widget<KeyedSubtree>(marker);
        expect(markerWidget.child, isA<RepaintBoundary>());
        final boundaryWidget = markerWidget.child as RepaintBoundary;
        expect(boundaryWidget.key, same(boundaryKey));
        expect(boundaryWidget.child, isA<SizedBox>());

        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        expect(boundary.size, hostSize);
        expect(metrics.documentSize, hostSize);
        expect(metrics.scale, 1);
        expect(metrics.origin, Offset.zero);

        final image = await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        );
        addTearDown(image!.dispose);
        expect(image.width, hostSize.width.round());
        expect(image.height, hostSize.height.round());
      });
    }

    testWidgets(
      'large host paints the document and cursor one-to-one with the host',
      (tester) async {
        final boundaryKey = GlobalKey();
        late DrawingViewportMetrics metrics;
        await _setHostSize(tester, const Size(1194, 834));
        await tester.pumpWidget(
          MaterialApp(
            home: DrawingCanvasViewport(
              repaintBoundaryKey: boundaryKey,
              canvas: const ColoredBox(color: Colors.white),
              overlayBuilder: (context, value) {
                metrics = value;
                return DrawingCursorOverlay(
                  state: const DrawingCursorState(
                    visible: true,
                    documentPosition: Offset(512, 384),
                    instrument: DrawingInstrument.brush,
                    eraserMode: DrawingEraserMode.area,
                    documentWidth: 64,
                    deviceKind: PointerDeviceKind.mouse,
                  ),
                  metrics: value,
                );
              },
            ),
          ),
        );
        await tester.pump();

        final boundary =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final topLeft = boundary.localToGlobal(Offset.zero);
        final bottomRight = boundary.localToGlobal(
          metrics.documentSize.bottomRight(Offset.zero),
        );
        // 종이가 곧 문서라 배율도 여백도 없다.
        expect(metrics.scale, 1);
        expect(metrics.documentSize, const Size(1194, 834));
        expect(topLeft, Offset.zero);
        expect(bottomRight, const Offset(1194, 834));

        final transformedWidth =
            (boundary.localToGlobal(const Offset(544, 384)) -
                    boundary.localToGlobal(const Offset(480, 384)))
                .distance;
        expect(transformedWidth, closeTo(64, 1e-9));
        // 커서는 선 굵기가 아니라 실제로 찍히는 자국 크기를 보여 준다.
        final footprint = DrawingStrokeRenderer.footprintFor(
          DrawingInstrument.brush.brushProfile,
          64,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('drawing-cursor-visual')))
              .width,
          closeTo(footprint * metrics.scale, 1e-9),
        );
      },
    );

    testWidgets(
      'maps document points without drift across rotation and a palette sheet',
      (tester) async {
        final boundaryKey = GlobalKey();
        await _setHostSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(home: _ViewportPaletteHarness(boundaryKey: boundaryKey)),
        );
        await tester.pump();

        const documentPoint = Offset(267.25, 403.5);
        Offset globalPoint() {
          final box =
              boundaryKey.currentContext!.findRenderObject()! as RenderBox;
          return box.localToGlobal(documentPoint);
        }

        final beforePalette = globalPoint();
        await tester.tap(find.byKey(const ValueKey('open-palette-sheet')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mobile-palette-sheet')),
          findsOneWidget,
        );
        expect(globalPoint(), beforePalette);

        Navigator.of(
          tester.element(find.byKey(const ValueKey('mobile-palette-sheet'))),
        ).pop();
        await tester.pumpAndSettle();
        expect(globalPoint(), beforePalette);

        await _setHostSize(tester, const Size(844, 390));
        await tester.pump();
        final box =
            boundaryKey.currentContext!.findRenderObject()! as RenderBox;
        final rotatedGlobal = box.localToGlobal(documentPoint);
        expect(box.globalToLocal(rotatedGlobal), documentPoint);
      },
    );

    testWidgets(
      'resize commits one active stroke and a later pointer up is a no-op',
      (tester) async {
        final documentController = DrawingDocumentController();
        final syncCoordinator = DrawingSyncCoordinator(
          sessionId: null,
          repository: null,
        );
        await _setHostSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(
            home: DrawingScreen(
              childId: '3',
              documentController: documentController,
              syncCoordinator: syncCoordinator,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final canvas = find.byKey(const ValueKey('drawing-canvas'));
        final gesture = await tester.startGesture(tester.getCenter(canvas));
        await gesture.moveBy(const Offset(12, 8));
        await tester.pump();
        expect(documentController.visibleStrokes, isEmpty);

        await _setHostSize(tester, const Size(844, 390));
        await tester.pump();
        expect(documentController.visibleStrokes, hasLength(1));
        final sequenceAfterResize = syncCoordinator.journal.lastEventSequence;

        await gesture.up();
        await tester.pump();
        expect(documentController.visibleStrokes, hasLength(1));
        expect(syncCoordinator.journal.lastEventSequence, sequenceAfterResize);
        await tester.pumpWidget(const SizedBox.shrink());
        syncCoordinator.dispose();
        documentController.dispose();
      },
    );

    testWidgets('pointer positions stay document-local after rotation', (
      tester,
    ) async {
      final documentController = DrawingDocumentController();
      final syncCoordinator = DrawingSyncCoordinator(
        sessionId: null,
        repository: null,
      );
      await _setHostSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(
            childId: '3',
            documentController: documentController,
            syncCoordinator: syncCoordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Size documentSize() =>
          tester.getSize(find.byKey(const ValueKey('drawing-canvas')));

      await _tapDocumentCenter(tester);
      final portraitSize = documentSize();
      final portraitPoint =
          documentController.visibleStrokes.single.points.first.position;

      await _setHostSize(tester, const Size(844, 390));
      await tester.pumpAndSettle();
      await _tapDocumentCenter(tester);
      final landscapeSize = documentSize();
      final landscapePoint =
          documentController.visibleStrokes.last.points.first.position;

      // 종이가 곧 문서라 크기는 방향마다 달라진다. 종이 한가운데를 찍으면 언제나
      // 문서 한가운데가 찍혀야 한다(S15P11B209-801).
      expect(landscapeSize, isNot(portraitSize));
      expect(portraitPoint.dx, closeTo(portraitSize.width / 2, 0.01));
      expect(portraitPoint.dy, closeTo(portraitSize.height / 2, 0.01));
      expect(landscapePoint.dx, closeTo(landscapeSize.width / 2, 0.01));
      expect(landscapePoint.dy, closeTo(landscapeSize.height / 2, 0.01));
      await tester.pumpWidget(const SizedBox.shrink());
      syncCoordinator.dispose();
      documentController.dispose();
    });

    testWidgets('does not dispose an injected document controller', (
      tester,
    ) async {
      final documentController = DrawingDocumentController();
      final syncCoordinator = DrawingSyncCoordinator(
        sessionId: null,
        repository: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(
            childId: '3',
            documentController: documentController,
            syncCoordinator: syncCoordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        () => documentController.addStroke(
          const DrawingStroke(
            points: [
              DrawingPoint(position: Offset.zero, elapsedMilliseconds: 0),
            ],
            color: Colors.black,
            thickness: 8,
          ),
        ),
        returnsNormally,
      );
      syncCoordinator.dispose();
      documentController.dispose();
    });
  });
}

Future<void> _setHostSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapDocumentCenter(WidgetTester tester) async {
  final canvas = find.byKey(const ValueKey('drawing-canvas'));
  final gesture = await tester.startGesture(tester.getCenter(canvas));
  await gesture.up();
  await tester.pump();
}

final class _ViewportPaletteHarness extends StatelessWidget {
  const _ViewportPaletteHarness({required this.boundaryKey});

  final GlobalKey boundaryKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        DrawingCanvasViewport(
          repaintBoundaryKey: boundaryKey,
          canvas: const ColoredBox(color: Colors.white),
          overlayBuilder: (context, metrics) => const SizedBox.expand(),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FilledButton(
            key: const ValueKey('open-palette-sheet'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => const SizedBox(
                key: ValueKey('mobile-palette-sheet'),
                height: 160,
              ),
            ),
            child: const Text('Palette'),
          ),
        ),
      ],
    ),
  );
}
