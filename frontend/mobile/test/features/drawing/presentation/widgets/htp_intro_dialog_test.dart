import 'package:dodam/features/drawing/presentation/widgets/htp_intro_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtpIntroDialog', () {
    testWidgets('소개 내용과 집·나무·사람 요소, 두 버튼을 보여준다', (tester) async {
      await _openDialog(tester);

      expect(find.text('집·나무·사람 그림 활동'), findsOneWidget);
      expect(find.text('집'), findsOneWidget);
      expect(find.text('나무'), findsOneWidget);
      expect(find.text('사람'), findsOneWidget);
      expect(find.textContaining('진단이 아니라'), findsOneWidget);
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('htp-intro-pastel-illustration')),
      );
      expect(image.fit, BoxFit.contain);
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/dialogs/dialog_htp_pastel.png',
      );
      expect(find.byKey(const ValueKey('htp-intro-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('htp-intro-cancel')), findsOneWidget);
    });

    testWidgets('시작하기를 누르면 true를 돌려준다', (tester) async {
      bool? result;
      await _openDialog(tester, onResult: (value) => result = value);

      await tester.tap(find.byKey(const ValueKey('htp-intro-start')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('취소를 누르면 false를 돌려준다', (tester) async {
      bool? result;
      await _openDialog(tester, onResult: (value) => result = value);

      await tester.tap(find.byKey(const ValueKey('htp-intro-cancel')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('좁은 화면과 2배 글자에서도 이미지를 자르지 않고 액션을 세로로 둔다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDialog(
        tester,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<Image>(
              find.byKey(const ValueKey('htp-intro-pastel-illustration')),
            )
            .fit,
        BoxFit.contain,
      );
      expect(
        find.byKey(const ValueKey('dodam-dialog-actions-column')),
        findsOneWidget,
      );
    });

    testWidgets('Pixel Tablet과 휴대폰 가로에서도 HTP 원본 비율과 카드 경계를 지킨다', (
      tester,
    ) async {
      for (final size in const [Size(1280, 800), Size(844, 390)]) {
        await tester.binding.setSurfaceSize(size);
        await _openDialog(tester, size: size);

        expect(tester.takeException(), isNull);
        final imageRect = tester.getRect(
          find.byKey(const ValueKey('htp-intro-pastel-illustration')),
        );
        final cardRect = tester.getRect(
          find.byKey(const ValueKey('dodam-dialog-card')),
        );
        expect(imageRect.width / imageRect.height, closeTo(1.5, 0.01));
        expect(cardRect.contains(imageRect.topLeft), isTrue);
        expect(cardRect.contains(imageRect.bottomRight), isTrue);

        await tester.tap(find.byKey(const ValueKey('htp-intro-cancel')));
        await tester.pumpAndSettle();
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  void Function(bool?)? onResult,
  Size size = const Size(800, 600),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: textScaler),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showHtpIntroDialog(context);
                  onResult?.call(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
