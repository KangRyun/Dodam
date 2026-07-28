import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MissingEmailOnboardingFlow', () {
    const flow = MissingEmailOnboardingFlow();

    test('백엔드가 이메일 추가 입력을 요구하면 입력 단계로 이동한다', () {
      expect(
        flow.resolve(_user(email: null, emailRequired: true)),
        MissingEmailOnboardingStep.emailInput,
      );
      expect(
        flow.resolve(_user(email: 'provider@email.test', emailRequired: true)),
        MissingEmailOnboardingStep.emailInput,
      );
    });

    test('백엔드가 이메일 추가 입력을 요구하지 않으면 입력 단계를 건너뛴다', () {
      expect(
        flow.resolve(
          _user(email: 'guardian@example.com', emailRequired: false),
        ),
        MissingEmailOnboardingStep.next,
      );
      expect(
        flow.resolve(_user(email: null, emailRequired: false)),
        MissingEmailOnboardingStep.next,
      );
    });
  });

  testWidgets('올바른 이메일의 공백을 제거해 제출한다', (tester) async {
    AdditionalEmailInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: AdditionalEmailScreen(
          onSubmit: (input) async => submitted = input,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  guardian@example.com  ');
    await _tapNext(tester);
    await tester.pumpAndSettle();

    expect(submitted?.email, 'guardian@example.com');
  });

  testWidgets('잘못된 이메일은 제출하지 않고 안내한다', (tester) async {
    var submitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdditionalEmailScreen(onSubmit: (_) async => submitCount += 1),
      ),
    );

    await tester.enterText(find.byType(TextField), 'wrong-email');
    await _tapNext(tester);
    await tester.pumpAndSettle();

    expect(submitCount, 0);
    expect(find.text('올바른 이메일 형식으로 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('제출 중 중복 요청을 막고 로딩을 표시한다', (tester) async {
    final completer = Completer<void>();
    var submitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdditionalEmailScreen(
          onSubmit: (_) {
            submitCount += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'guardian@example.com');
    await _tapNext(tester);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('additional-email-next')),
        matching: find.byType(FilledButton),
      ),
    );

    expect(submitCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('저장 실패 시 다시 시도할 수 있는 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdditionalEmailScreen(
          onSubmit: (_) async => throw Exception('save failed'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'guardian@example.com');
    await _tapNext(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('additional-email-failure')),
      findsOneWidget,
    );
  });
}

Future<void> _tapNext(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('additional-email-next'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: button, matching: find.byType(FilledButton)),
  );
}

AuthenticatedUser _user({
  required String? email,
  required bool emailRequired,
}) => AuthenticatedUser(
  id: 'user-1',
  provider: AuthProvider.naver,
  providerUserId: 'naver-user-1',
  role: UserRole.guardian,
  onboardingCompleted: false,
  emailRequired: emailRequired,
  email: email,
);
