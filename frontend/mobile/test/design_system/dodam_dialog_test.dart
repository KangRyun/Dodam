import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DodamDialog', () {
    testWidgets('파스텔 카드·warning 일러스트·sage scrim을 사용한다', (tester) async {
      await _openConfirmDialog(tester);

      final card = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('dodam-dialog-card')),
      );
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(decoration.border, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
      expect(
        find.byKey(const ValueKey('dodam-dialog-warning-illustration')),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('dodam-dialog-warning-illustration')),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier && widget.color == dodamDialogScrim,
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('정말 나갈까요?')).flagsCollection.isHeader,
        isTrue,
      );
    });

    testWidgets('취소·확인 순서와 위험 액션 반환값을 유지한다', (tester) async {
      bool? result;
      await _openConfirmDialog(
        tester,
        isDanger: true,
        confirmLabel: '삭제',
        onResult: (value) => result = value,
      );

      final buttons = tester
          .widgetList<DodamDialogButton>(find.byType(DodamDialogButton))
          .toList();
      expect(buttons.map((button) => button.label), ['취소', '삭제']);
      expect(buttons.last.kind, DodamDialogButtonKind.danger);

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('좁은 화면과 2배 글자에서는 버튼을 세로로 놓고 48dp를 지킨다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openConfirmDialog(
        tester,
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 640),
        message:
            '아주 긴 안내 문구가 여러 줄로 표시되어도 내용과 버튼이 잘리지 않아야 합니다. '
            '사용자는 스크롤한 뒤 안전하게 선택할 수 있어야 합니다.',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('dodam-dialog-actions-column')),
        findsOneWidget,
      );
      for (final button in find.byType(DodamDialogButton).evaluate()) {
        expect(button.size!.height, greaterThanOrEqualTo(48));
        expect(button.size!.width, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('Pixel Tablet과 휴대폰 가로에서도 카드가 viewport 안에 머문다', (tester) async {
      for (final configuration in const [
        (size: Size(1280, 800), textScaler: TextScaler.noScaling),
        (size: Size(844, 390), textScaler: TextScaler.noScaling),
        (size: Size(844, 390), textScaler: TextScaler.linear(2)),
      ]) {
        await tester.binding.setSurfaceSize(configuration.size);
        await _openConfirmDialog(
          tester,
          size: configuration.size,
          textScaler: configuration.textScaler,
        );

        expect(tester.takeException(), isNull);
        final cardRect = tester.getRect(
          find.byKey(const ValueKey('dodam-dialog-card')),
        );
        expect(cardRect.left, greaterThanOrEqualTo(0));
        expect(cardRect.top, greaterThanOrEqualTo(0));
        expect(cardRect.right, lessThanOrEqualTo(configuration.size.width));
        expect(cardRect.bottom, lessThanOrEqualTo(configuration.size.height));

        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}

Future<void> _openConfirmDialog(
  WidgetTester tester, {
  bool isDanger = false,
  String confirmLabel = '확인',
  String message = '저장하지 않은 내용은 사라져요.',
  Size size = const Size(800, 600),
  TextScaler textScaler = TextScaler.noScaling,
  void Function(bool?)? onResult,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: textScaler),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showAppConfirmDialog(
                  context: context,
                  title: '정말 나갈까요?',
                  message: message,
                  confirmLabel: confirmLabel,
                  isDanger: isDanger,
                );
                onResult?.call(result);
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}
