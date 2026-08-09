import 'package:dodam/features/drawing/presentation/widgets/drawing_complete_cta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrawingCompleteCta', () {
    testWidgets('keeps a coloured crayon surface with a white label', (
      tester,
    ) async {
      await _pump(tester);

      final material = tester.widget<Material>(
        find.byKey(const ValueKey('drawing-complete')),
      );
      final label = tester.widget<Text>(find.text('다 그렸어요!'));

      expect(material.color, isNot(Colors.white));
      expect(label.style?.color, Colors.white);
      expect(
        find.byKey(const ValueKey('drawing-complete-crayon-texture')),
        findsOneWidget,
      );
    });

    testWidgets('아이가 읽을 문구와 48px 이상 터치 영역을 제공한다', (tester) async {
      await _pump(tester);

      final actual = find.byKey(const ValueKey('drawing-complete'));
      final compatibility = find.byKey(
        const ValueKey('drawing-complete-button'),
      );
      // 툴바에서 옮겨 오며 Key 를 유지했다. 완료 흐름 테스트가 이 이름을 쓴다.
      expect(actual, findsOneWidget);
      expect(
        find.descendant(of: compatibility, matching: actual),
        findsOneWidget,
      );
      expect(find.text('다 그렸어요!'), findsOneWidget);

      final size = tester.getSize(actual);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('2배 글자에서도 글씨를 줄이지 않는다', (tester) async {
      await _pump(tester, textScale: 2);

      final actual = find.byKey(const ValueKey('drawing-complete'));
      expect(
        find.descendant(of: actual, matching: find.byType(FittedBox)),
        findsNothing,
      );
      final label = tester.widget<Text>(
        find.descendant(of: actual, matching: find.byType(Text)),
      );
      expect(label.style?.fontSize, greaterThanOrEqualTo(19));
      expect(tester.getSize(actual).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('보낼 그림이 없으면 탭도 semantics tap도 받지 않는다', (tester) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      await _pump(tester, enabled: false, onPressed: () => presses++);

      final actual = find.byKey(const ValueKey('drawing-complete'));
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: actual, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .getSemantics(actual)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(actual, warnIfMissed: false);
      expect(presses, 0);
      semantics.dispose();
    });

    testWidgets('전송 중에는 진행 표시를 띄우고 다시 누르지 못한다', (tester) async {
      var presses = 0;
      await _pump(tester, isCompleting: true, onPressed: () => presses++);

      final actual = find.byKey(const ValueKey('drawing-complete'));
      expect(
        find.descendant(
          of: actual,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('완성하는 중'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: actual, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
      );
      await tester.tap(actual, warnIfMissed: false);
      expect(presses, 0);
    });

    testWidgets('semantics tap 한 번에 완료를 한 번만 부른다', (tester) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      await _pump(tester, onPressed: () => presses++);

      final target = find.semantics.byLabel('그림 완료');
      expect(target, findsOne);
      expect(target, isSemantics(hasTapAction: true));
      tester.semantics.tap(target);
      await tester.pump();
      expect(presses, 1);
      semantics.dispose();
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool isCompleting = false,
  double textScale = 1,
  VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        floatingActionButton: DrawingCompleteCta(
          enabled: enabled,
          isCompleting: isCompleting,
          onPressed: onPressed ?? () {},
        ),
      ),
    ),
  );
  if (isCompleting) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}
