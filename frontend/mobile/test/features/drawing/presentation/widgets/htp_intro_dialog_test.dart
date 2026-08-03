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
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  void Function(bool?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
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
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
