import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/drawing/application/canvas_tutorial_controller.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_tutorial_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('도구 단계를 순서대로 안내하고 마지막에 닫는다', (tester) async {
    final controller = _replayController();
    await _pump(tester, controller);

    expect(find.text('도구를 골라 그려요'), findsOneWidget);
    expect(find.text('1 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pump();
    expect(find.text('지우개로 고쳐요'), findsOneWidget);

    for (var index = 0; index < 4; index += 1) {
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await tester.pump();
    }
    expect(find.text('그림을 마쳐요'), findsOneWidget);
    expect(find.text('6 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pump();
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
  });

  testWidgets('이전 단계와 건너뛰기를 제공한다', (tester) async {
    final controller = _replayController();
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tutorial-previous')));
    await tester.pump();
    expect(find.text('도구를 골라 그려요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pump();
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
  });

  testWidgets('조회 오류는 다시 시도와 그림 계속 그리기를 제공한다', (tester) async {
    var shouldFail = true;
    final controller = CanvasTutorialController(
      childId: 7,
      loadProgress: (_) async {
        if (shouldFail) throw StateError('offline');
        return _progress(status: 'COMPLETED');
      },
      saveProgress: (_, _) async => _progress(status: 'IN_PROGRESS'),
    );
    await controller.load();
    await _pump(tester, controller);

    expect(find.text('도구 안내를 불러오지 못했어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('tutorial-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('tutorial-continue')), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.byKey(const ValueKey('tutorial-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
  });

  testWidgets('단계 저장 오류의 다시 시도는 같은 단계 이동을 재실행한다', (tester) async {
    var shouldFail = true;
    final controller = CanvasTutorialController(
      childId: 7,
      loadProgress: (_) async =>
          _progress(status: 'IN_PROGRESS', lastStep: 'PEN'),
      saveProgress: (_, request) async {
        if (shouldFail) throw StateError('timeout');
        return _progress(
          status: request.tutorialStatus,
          lastStep: request.lastStep,
        );
      },
    );
    await controller.load();
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();
    expect(find.text('도구 안내를 불러오지 못했어요'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.byKey(const ValueKey('tutorial-retry')));
    await tester.pumpAndSettle();
    expect(find.text('지우개로 고쳐요'), findsOneWidget);
  });

  testWidgets('작은 가로 화면과 큰 글자에서도 overflow가 없다', (tester) async {
    tester.view.physicalSize = const Size(844, 419);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _replayController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            body: Stack(children: [CanvasToolTutorialOverlay(controller)]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsOneWidget);
  });

  testWidgets('태블릿에서는 캐릭터가 화면 폭에 비례해 커지고 카드와 겹치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _replayController();
    await _pump(tester, controller);

    final teacher = tester.getRect(
      find.byKey(const ValueKey('canvas-tutorial-teacher')),
    );
    final bubble = tester.getRect(
      find.byKey(const ValueKey('canvas-tutorial-bubble')),
    );
    expect(teacher.width, inInclusiveRange(1280 * 0.24, 1280 * 0.30));
    expect(teacher.right, lessThanOrEqualTo(bubble.left));
    expect(teacher.bottom, lessThanOrEqualTo(800));

    final next = tester.getRect(find.byKey(const ValueKey('tutorial-next')));
    expect(next.height, greaterThanOrEqualTo(48));
    expect(next.width, lessThan(bubble.width * 0.65));
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-tutorial-dots'))).right,
      lessThan(next.left),
    );
  });

  testWidgets('세 가지 viewport와 2배 글자에서 콘텐츠와 동작이 overflow 없이 유지된다', (
    tester,
  ) async {
    for (final size in const [
      Size(390, 844),
      Size(844, 390),
      Size(1280, 800),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final controller = _replayController();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Stack(children: [CanvasToolTutorialOverlay(controller)]),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('도구를 골라 그려요'), findsOneWidget, reason: '$size');
      expect(find.text('1 / 6'), findsOneWidget, reason: '$size');
      expect(
        find.byKey(const ValueKey('tutorial-next')),
        findsOneWidget,
        reason: '$size',
      );
      expect(
        find.byKey(const ValueKey('tutorial-skip')),
        findsOneWidget,
        reason: '$size',
      );
    }
    addTearDown(tester.view.reset);
  });
}

CanvasTutorialController _replayController() {
  final controller = CanvasTutorialController(
    childId: 7,
    loadProgress: (_) async => _progress(status: 'COMPLETED'),
    saveProgress: (_, _) async => _progress(status: 'COMPLETED'),
  );
  controller.replay();
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  CanvasTutorialController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(children: [CanvasToolTutorialOverlay(controller)]),
      ),
    ),
  );
  await tester.pump();
}

TutorialProgressDto _progress({required String status, String? lastStep}) =>
    TutorialProgressDto(
      childId: 7,
      tutorialStatus: status,
      lastStep: lastStep,
      completedAt: null,
      updatedAt: '2026-07-31T00:00:00Z',
    );
