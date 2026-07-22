import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('보호자와 전문가 역할만 선택할 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingProfileScreen(onSubmit: (_) async {})),
    );

    expect(
      find.byKey(const ValueKey('onboarding-role-guardian')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-role-expert')),
      findsOneWidget,
    );
    expect(find.text('관리자'), findsNothing);
  });

  testWidgets('역할과 닉네임을 입력하면 기본 정보를 전달한다', (tester) async {
    OnboardingProfileInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingProfileScreen(
          onSubmit: (input) async => submitted = input,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('onboarding-role-guardian-tap')),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  민지엄마  ');
    final nextButton = find.byKey(const ValueKey('onboarding-profile-next'));
    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: nextButton, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(submitted?.role, UserRole.guardian);
    expect(submitted?.nickname, '민지엄마');
  });

  testWidgets('제출 중에는 중복 요청을 막는다', (tester) async {
    final completer = Completer<void>();
    var submitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingProfileScreen(
          onSubmit: (_) {
            submitCount += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('onboarding-role-expert-tap')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '김하늘 상담사');
    final nextButton = find.byKey(const ValueKey('onboarding-profile-next'));
    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    final filledButton = find.descendant(
      of: nextButton,
      matching: find.byType(FilledButton),
    );
    await tester.tap(filledButton);
    await tester.pump();
    await tester.tap(filledButton);

    expect(submitCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('작은 화면에서도 오버플로 없이 표시한다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: OnboardingProfileScreen(onSubmit: (_) async {})),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
