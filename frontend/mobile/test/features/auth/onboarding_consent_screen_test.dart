import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('필수 약관에 모두 동의해야 완료할 수 있다', (tester) async {
    ConsentAgreementInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (input) async => submitted = input,
        ),
      ),
    );

    final submit = find.byKey(const ValueKey('consent-submit'));
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: submit, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );

    for (final code in const [
      ConsentCode.serviceTerms,
      ConsentCode.childPrivacy,
      ConsentCode.drawingAnalysis,
    ]) {
      await tester.tap(find.byKey(ValueKey('consent-${code.name}')));
      await tester.pump();
    }
    await tester.ensureVisible(submit);
    await tester.tap(
      find.descendant(of: submit, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.agreedConsents.length, 3);
    expect(submitted!.isAgreed(ConsentCode.voiceProcessing), isFalse);
  });

  testWidgets('전체 동의는 모든 필수·선택 항목을 선택하고 해제한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingConsentScreen(onSubmit: (_) async {})),
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((checkbox) => checkbox.value == true),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((checkbox) => checkbox.value == false),
      isTrue,
    );
  });

  testWidgets('제출 중에는 중복 요청을 막는다', (tester) async {
    final completer = Completer<void>();
    var submitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (_) {
            submitCount += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    final submit = find.byKey(const ValueKey('consent-submit'));
    await tester.ensureVisible(submit);
    final button = find.descendant(
      of: submit,
      matching: find.byType(FilledButton),
    );
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);

    expect(submitCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('저장 실패 시 다시 시도할 수 있는 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (_) => Future<void>.error(Exception('failed')),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    final submit = find.byKey(const ValueKey('consent-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(
      find.descendant(of: submit, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('consent-submit-error')), findsOneWidget);
  });

  testWidgets('작은 화면에서도 오버플로 없이 표시한다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: OnboardingConsentScreen(onSubmit: (_) async {})),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
