import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowWidthClass', () {
    test('폭 구간 경계를 정확히 나눈다', () {
      expect(WindowWidthClass.fromWidth(599), WindowWidthClass.compact);
      expect(WindowWidthClass.fromWidth(600), WindowWidthClass.medium);
      expect(WindowWidthClass.fromWidth(839), WindowWidthClass.medium);
      expect(WindowWidthClass.fromWidth(840), WindowWidthClass.expanded);
      expect(WindowWidthClass.fromWidth(1199), WindowWidthClass.expanded);
      expect(WindowWidthClass.fromWidth(1200), WindowWidthClass.large);
      expect(WindowWidthClass.fromWidth(1440), WindowWidthClass.large);
    });

    test('편의 접근자가 구간을 올바르게 판정한다', () {
      expect(WindowWidthClass.compact.isCompact, isTrue);
      expect(WindowWidthClass.medium.isCompact, isFalse);
      expect(WindowWidthClass.medium.isExpandedOrWider, isFalse);
      expect(WindowWidthClass.expanded.isExpandedOrWider, isTrue);
      expect(WindowWidthClass.large.isExpandedOrWider, isTrue);
    });

    testWidgets('context.widthClass가 MediaQuery 폭을 읽는다', (tester) async {
      late WindowWidthClass seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1000, 700)),
          child: Builder(
            builder: (context) {
              seen = context.widthClass;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, WindowWidthClass.expanded);
    });
  });

  group('ResponsiveContent', () {
    Future<Size> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ResponsiveContent(
            maxWidth: 1000,
            child: SizedBox(
              key: const ValueKey('child'),
              height: 100,
              child: Container(color: const Color(0xFF000000)),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byKey(const ValueKey('child')));
    }

    testWidgets('가용 폭이 상한보다 넓으면 상한으로 가둔다', (tester) async {
      final size = await pumpAt(tester, 1400);
      expect(size.width, 1000);
    });

    testWidgets('가용 폭이 상한보다 좁으면 폭을 온전히 채운다', (tester) async {
      final size = await pumpAt(tester, 700);
      expect(size.width, 700);
    });

    testWidgets('넓은 화면에서 자식을 가로 가운데에 둔다', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ResponsiveContent(
            maxWidth: 1000,
            child: SizedBox(key: ValueKey('child'), width: 1000, height: 100),
          ),
        ),
      );
      await tester.pump();

      final rect = tester.getRect(find.byKey(const ValueKey('child')));
      // 1400 폭 안에서 1000 폭 박스가 가운데 → 양쪽 여백 200씩.
      expect(rect.left, moreOrLessEquals(200, epsilon: 0.5));
      expect(rect.right, moreOrLessEquals(1200, epsilon: 0.5));
    });

    testWidgets('세로 제약을 통과시켜 Expanded 자식이 남은 높이를 채운다', (tester) async {
      tester.view.physicalSize = const Size(1400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ResponsiveContent(
            maxWidth: 1000,
            child: Column(
              children: [
                SizedBox(height: 100),
                Expanded(child: SizedBox(key: ValueKey('filler'))),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Column이 세로를 채우므로 Expanded가 남은 500을 받는다(오버플로 예외 없음).
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('filler'))).height,
        500,
      );
    });
  });
}
