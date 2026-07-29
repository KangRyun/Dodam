import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('그림 도구 패널 접근성', () {
    testWidgets('색상·굵기 선택과 실행취소 버튼은 48×48 이상의 터치 영역을 가진다', (tester) async {
      await _pumpDrawing(tester);

      for (final name in ['검정', '빨강', '파랑', '노랑']) {
        final size = tester.getSize(find.byKey(ValueKey('color-$name')));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }

      for (final label in ['얇게', '보통', '굵게']) {
        final size = tester.getSize(
          find.byKey(ValueKey('drawing-thickness-$label')),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }

      final undoSize = tester.getSize(
        find.byKey(const ValueKey('undo-action')),
      );
      expect(undoSize.width, greaterThanOrEqualTo(48));
      expect(undoSize.height, greaterThanOrEqualTo(48));
    });

    testWidgets('펜·지우개·색상·굵기 선택 요소는 Semantics 라벨을 제공한다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDrawing(tester);

      expect(find.bySemanticsLabel(RegExp('^펜 도구')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^지우개 도구')), findsOneWidget);
      expect(find.bySemanticsLabel('검정 색상'), findsOneWidget);
      expect(find.bySemanticsLabel('빨강 색상'), findsOneWidget);
      expect(find.bySemanticsLabel('파랑 색상'), findsOneWidget);
      expect(find.bySemanticsLabel('노랑 색상'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^얇게 굵기')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^보통 굵기')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^굵게 굵기')), findsOneWidget);

      handle.dispose();
    });

    testWidgets('색상 선택 상태는 테두리 두께·체크 아이콘으로 구분되며 색상만으로 구분하지 않는다', (
      tester,
    ) async {
      await _pumpDrawing(tester);

      final redSwatch = find.byKey(const ValueKey('color-빨강'));
      await tester.tap(redSwatch);
      await tester.pumpAndSettle();

      final selectedBorder = _swatchBorder(tester, redSwatch);
      expect(selectedBorder.top.width, 4);
      expect(
        find.descendant(
          of: redSwatch,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );

      final blackSwatch = find.byKey(const ValueKey('color-검정'));
      final unselectedBorder = _swatchBorder(tester, blackSwatch);
      expect(unselectedBorder.top.width, 2);
      expect(
        find.descendant(
          of: blackSwatch,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('시스템 글자 크기를 2배로 확대해도 도구 패널 제목에서 overflow가 발생하지 않는다', (
      tester,
    ) async {
      await _pumpDrawing(tester, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('도구'), findsOneWidget);
      expect(find.text('색상'), findsOneWidget);
      expect(find.text('굵기'), findsOneWidget);
      expect(find.text('펜'), findsOneWidget);
      expect(find.text('지우개'), findsOneWidget);
    });
  });
}

Border _swatchBorder(WidgetTester tester, Finder swatch) {
  final container = tester.widget<Container>(
    find.descendant(of: swatch, matching: find.byType(Container)),
  );
  return (container.decoration! as BoxDecoration).border! as Border;
}

Future<void> _pumpDrawing(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  double textScale = 1.0,
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
