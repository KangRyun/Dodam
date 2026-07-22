import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('이메일이 제공된 사용자는 기본 정보 다음에 약관으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NewUserOnboardingFlowScreen(
          needsEmail: false,
          onComplete: (_) async {},
        ),
      ),
    );

    await _submitProfile(tester);

    expect(
      find.byKey(const ValueKey('onboarding-flow-consent')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('onboarding-flow-email')), findsNothing);
  });

  testWidgets('이메일 미제공 사용자는 추가 입력 후 약관으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NewUserOnboardingFlowScreen(
          needsEmail: true,
          onComplete: (_) async {},
        ),
      ),
    );

    await _submitProfile(tester);
    expect(find.byKey(const ValueKey('onboarding-flow-email')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'guardian@dodam.test');
    final submit = find.byKey(const ValueKey('additional-email-next'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: submit, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('onboarding-flow-consent')),
      findsOneWidget,
    );
  });
}

Future<void> _submitProfile(WidgetTester tester) async {
  final role = find.byKey(const ValueKey('onboarding-role-guardian-tap'));
  await tester.ensureVisible(role);
  await tester.tap(role);
  await tester.pump();
  await tester.enterText(find.byType(TextField), '민지엄마');
  final submit = find.byKey(const ValueKey('onboarding-profile-next'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  final button = find.descendant(
    of: submit,
    matching: find.byType(FilledButton),
  );
  expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
