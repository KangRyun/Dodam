import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('자체 로그인 없이 소셜 로그인 버튼 3개를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SocialLoginScreen(onSignIn: (_) async {})),
    );

    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('구글로 시작하기'), findsOneWidget);
    expect(find.text('네이버로 시작하기'), findsOneWidget);
    expect(find.text('아이디'), findsNothing);
    expect(find.text('비밀번호'), findsNothing);
  });

  testWidgets('선택한 Provider를 전달하고 요청 중 중복 탭을 막는다', (tester) async {
    final completer = Completer<void>();
    final providers = <AuthProvider>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SocialLoginScreen(
          onSignIn: (provider) {
            providers.add(provider);
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pump();
    await tester.tap(find.text('구글로 시작하기'));

    expect(providers, [AuthProvider.kakao]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('작은 휴대폰 화면에서도 오버플로 없이 표시한다', (tester) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: SocialLoginScreen(onSignIn: (_) async {})),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('그림과 대화로\n아이의 마음을 만나봐요'), findsOneWidget);
  });
}
