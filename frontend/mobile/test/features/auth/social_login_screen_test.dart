import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/reduced_motion.dart';

void main() {
  useReducedMotionForTests();

  testWidgets('자체 로그인 없이 소셜 로그인 버튼 3개를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SocialLoginScreen(onSignIn: (_) async {})),
    );

    expect(find.byKey(const ValueKey('social-login-kakao')), findsOneWidget);
    expect(find.byKey(const ValueKey('social-login-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('social-login-naver')), findsOneWidget);
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

    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('social-login-google')));

    expect(providers, [AuthProvider.kakao]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('카카오 계정으로 연결하고 있어요…'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('로그인 취소는 별도 안내 없이 기본 화면으로 복귀한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SocialLoginScreen(
          onSignIn: (_) async => throw const AuthFailure(
            type: AuthFailureType.cancelled,
            message: 'cancelled',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('로그인을 완료하지 못했어요'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('재시도 가능한 실패는 원인 안내와 다시 시도 버튼을 보여준다', (tester) async {
    var attemptCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SocialLoginScreen(
          onSignIn: (_) async {
            attemptCount += 1;
            throw const AuthFailure(
              type: AuthFailureType.network,
              message: 'network error',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-google')));
    await tester.pumpAndSettle();

    expect(find.text('로그인을 완료하지 못했어요'), findsOneWidget);
    expect(find.textContaining('인터넷 연결이 불안정해요'), findsOneWidget);

    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(attemptCount, 2);
  });

  testWidgets('재시도할 수 없는 계정 실패에는 다시 시도 버튼을 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SocialLoginScreen(
          onSignIn: (_) async => throw const AuthFailure(
            type: AuthFailureType.accountSuspended,
            message: 'suspended',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-naver')));
    await tester.pumpAndSettle();

    expect(find.textContaining('고객센터에 문의'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('OAuth 설정 오류는 재로그인이 아닌 앱 설정 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SocialLoginScreen(
          onSignIn: (_) async => throw const AuthFailure(
            type: AuthFailureType.configuration,
            message: 'configuration error',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-google')));
    await tester.pumpAndSettle();

    expect(find.textContaining('앱 로그인 설정을 확인해 주세요'), findsOneWidget);
    expect(find.textContaining('다시 로그인해 주세요'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
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
