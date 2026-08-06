import 'dart:async';

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/child_mode/presentation/widgets/activity_guide_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActivityGuideDialog', () {
    testWidgets('그림일기 파스텔 일러스트와 기존 문구·accent를 유지한다', (tester) async {
      await _openActivityGuide(tester, onStart: () async => 'started');

      final image = tester.widget<Image>(
        find.byKey(const ValueKey('activity-guide-diary-illustration')),
      );
      expect((image.image as AssetImage).assetName, DodamDialogAssets.diary);
      expect(image.fit, BoxFit.contain);
      expect(find.text('그림일기'), findsOneWidget);
      expect(find.text('오늘 있었던 일을 그림으로 남겨 볼까?'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.menu_book_rounded)).color,
        AppColors.tangerine,
      );
    });

    testWidgets('loading 중 연속 탭은 시작 콜백을 한 번만 실행한다', (tester) async {
      final completer = Completer<String>();
      var calls = 0;
      String? result;
      await _openActivityGuide(
        tester,
        onStart: () {
          calls++;
          return completer.future;
        },
        onResult: (value) => result = value,
      );

      final start = find.byKey(const ValueKey('activity-guide-start'));
      await tester.tap(start);
      await tester.tap(start);
      await tester.pump();

      expect(calls, 1);
      expect(tester.widget<DodamDialogButton>(start).loading, isTrue);

      completer.complete('started');
      await tester.pumpAndSettle();
      expect(result, 'started');
    });

    testWidgets('오류를 live region으로 알리고 다시 시도한다', (tester) async {
      var calls = 0;
      String? result;
      await _openActivityGuide(
        tester,
        onStart: () async {
          calls++;
          if (calls == 1) throw StateError('failed');
          return 'retried';
        },
        onResult: (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('activity-guide-error')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
      expect(find.text('다시 시도'), findsOneWidget);

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(result, 'retried');
    });

    testWidgets('좁은 화면과 2배 글자에서도 overflow 없이 세로 액션을 쓴다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openActivityGuide(
        tester,
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 640),
        description: '오늘 있었던 일을 아주 길게 자세히 적어 보면서 그림으로도 함께 그려 볼까?',
        onStart: () => Completer<String>().future,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('dodam-dialog-actions-column')),
        findsOneWidget,
      );
    });

    testWidgets('Pixel Tablet과 휴대폰 가로에서 일러스트가 카드 안에 배치된다', (tester) async {
      for (final size in const [Size(1280, 800), Size(844, 390)]) {
        await tester.binding.setSurfaceSize(size);
        await _openActivityGuide(
          tester,
          size: size,
          onStart: () async => 'started',
        );

        expect(tester.takeException(), isNull);
        final imageRect = tester.getRect(
          find.byKey(const ValueKey('activity-guide-diary-illustration')),
        );
        final cardRect = tester.getRect(
          find.byKey(const ValueKey('dodam-dialog-card')),
        );
        expect(cardRect.contains(imageRect.topLeft), isTrue);
        expect(cardRect.contains(imageRect.bottomRight), isTrue);

        await tester.tap(find.byKey(const ValueKey('activity-guide-cancel')));
        await tester.pumpAndSettle();
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}

Future<void> _openActivityGuide(
  WidgetTester tester, {
  required Future<String> Function() onStart,
  String description = '오늘 있었던 일을 그림으로 남겨 볼까?',
  Size size = const Size(800, 600),
  TextScaler textScaler = TextScaler.noScaling,
  void Function(String?)? onResult,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: textScaler),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showActivityGuideDialog<String>(
                  context: context,
                  title: '그림일기',
                  description: description,
                  icon: Icons.menu_book_rounded,
                  accentColor: AppColors.tangerine,
                  onStart: onStart,
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
