import 'dart:async';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/guardian_pin/data/dto/guardian_pin_dtos.dart';
import 'package:dodam/features/guardian_pin/domain/failures/guardian_pin_failure.dart';
import 'package:dodam/features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import 'package:dodam/features/guardian_pin/presentation/screens/guardian_pin_gate_screen.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_pin_input.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_pin_panel.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_reauth_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PIN 잊음 → 소셜 재인증 → 서버 초기화 → 새 PIN 설정 복구 경로(S15P11B209-874).
///
/// 백엔드 `DELETE users/me/guardian-pin`은 현재 PIN 없이 세션만으로 지운다.
/// 그래서 초기화 앞의 재인증이 유일한 방어선이고, 여기서 그 방어선이 실제로
/// 서는지를 확인한다.
void main() {
  group('gate 화면', () {
    testWidgets('확인 흐름에서만 재설정 진입점을 보여준다', (tester) async {
      await _pumpGate(tester, repository: _ResetRepository());
      expect(find.byKey(guardianPinForgotKey), findsOneWidget);
      expect(find.text('PIN을 잊으셨나요?'), findsOneWidget);
    });

    testWidgets('설정 흐름에는 지울 PIN이 없어 진입점을 숨긴다', (tester) async {
      await _pumpGate(
        tester,
        repository: _ResetRepository(pinConfigured: false),
      );
      expect(find.text('보호자 PIN 설정'), findsOneWidget);
      expect(find.byKey(guardianPinForgotKey), findsNothing);
    });

    testWidgets('재인증에 성공하면 초기화하고 새 PIN 설정으로 이어진다', (tester) async {
      final repository = _ResetRepository();
      var unlocked = 0;
      await _pumpGate(
        tester,
        repository: repository,
        onReauthenticate: () async => true,
        onUnlocked: () => unlocked += 1,
      );

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pumpAndSettle();

      expect(repository.resetCalls, 1);
      expect(find.text('보호자 PIN 설정'), findsOneWidget);
      // 초기화 뒤에는 지울 PIN이 없으므로 진입점도 사라진다.
      expect(find.byKey(guardianPinForgotKey), findsNothing);

      await _submitPin(tester, '2468');
      await _submitPin(tester, '2468');

      expect(repository.configuredPins, ['2468']);
      expect(repository.verifiedPins, isEmpty);
      expect(unlocked, 1);
    });

    testWidgets('재인증을 마치지 못하면 초기화하지 않고 gate를 유지한다', (tester) async {
      final repository = _ResetRepository();
      await _pumpGate(
        tester,
        repository: repository,
        onReauthenticate: () async => false,
      );

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pumpAndSettle();

      expect(repository.resetCalls, 0);
      expect(find.textContaining('본인 확인을 마치지 못했어요'), findsOneWidget);
      // 확인 흐름 그대로 — 새 PIN을 세울 수 있는 상태가 되면 안 된다.
      expect(find.text('보호자 확인'), findsOneWidget);
      expect(find.byKey(guardianPinForgotKey), findsOneWidget);
    });

    testWidgets('초기화가 실패하면 서버가 준 사유를 보여주고 gate를 유지한다', (tester) async {
      final repository = _ResetRepository(
        resetError: const GuardianPinFailure(
          type: GuardianPinFailureType.unavailable,
          code: 'PIN_UNAVAILABLE',
        ),
      );
      await _pumpGate(
        tester,
        repository: repository,
        onReauthenticate: () async => true,
      );

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pumpAndSettle();

      expect(repository.resetCalls, 1);
      expect(find.textContaining('지금은 PIN 기능을 사용할 수 없어요'), findsOneWidget);
      expect(find.text('보호자 확인'), findsOneWidget);
    });

    testWidgets('서버 잠금 상태에서도 재설정으로 빠져나갈 수 있다', (tester) async {
      final repository = _ResetRepository(locked: true, retryAfterSeconds: 45);
      await _pumpGate(
        tester,
        repository: repository,
        onReauthenticate: () async => true,
      );

      // 입력은 잠겨 있어도 탈출구는 열려 있어야 한다.
      expect(
        tester.widget<TextField>(find.byKey(guardianPinTextFieldKey)).enabled,
        isFalse,
      );
      expect(find.textContaining('45초'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(guardianPinForgotKey)).onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pumpAndSettle();

      expect(repository.resetCalls, 1);
      expect(find.text('보호자 PIN 설정'), findsOneWidget);
    });

    testWidgets('재설정 중 재탭은 재인증도 초기화도 중복 실행하지 않는다', (tester) async {
      final pending = Completer<bool>();
      final repository = _ResetRepository();
      var reauthCalls = 0;
      await _pumpGate(
        tester,
        repository: repository,
        onReauthenticate: () {
          reauthCalls += 1;
          return pending.future;
        },
      );

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byKey(guardianPinForgotKey)).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pump();
      expect(reauthCalls, 1);
      expect(repository.resetCalls, 0);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(reauthCalls, 1);
      expect(repository.resetCalls, 1);
    });

    testWidgets('재인증 배선이 없으면 진입점을 숨긴다', (tester) async {
      // 배선이 빠져도 gate 자체는 서야 한다 — 복구 경로만 사라진다.
      await _pumpGate(
        tester,
        repository: _ResetRepository(),
        wireReauth: false,
      );
      expect(find.byKey(guardianPinGateKey), findsOneWidget);
      expect(find.byKey(guardianPinForgotKey), findsNothing);
    });
  });

  group('계정 동일성', () {
    testWidgets('같은 계정으로 재로그인하면 초기화한다', (tester) async {
      final repository = _ResetRepository();
      final auth = _FakeAuthRepository(
        restoredSession: _session('guardian-1'),
        signInSession: _session('guardian-1'),
      );
      await _pumpAppToGate(tester, repository: repository, auth: auth);

      await _reauthenticateWithKakao(tester);

      expect(auth.signInCalls, 1);
      expect(repository.resetCalls, 1);
      expect(find.text('보호자 PIN 설정'), findsOneWidget);
    });

    testWidgets('다른 계정으로 로그인되면 초기화하지 않는다', (tester) async {
      final repository = _ResetRepository();
      final auth = _FakeAuthRepository(
        restoredSession: _session('guardian-1'),
        signInSession: _session('guardian-2'),
      );
      await _pumpAppToGate(tester, repository: repository, auth: auth);

      await _reauthenticateWithKakao(tester);

      expect(auth.signInCalls, 1);
      expect(repository.resetCalls, 0);
      expect(find.textContaining('본인 확인을 마치지 못했어요'), findsOneWidget);
      expect(find.text('보호자 확인'), findsOneWidget);
    });

    testWidgets('본인확인 시트를 취소하면 로그인도 초기화도 하지 않는다', (tester) async {
      final repository = _ResetRepository();
      final auth = _FakeAuthRepository(
        restoredSession: _session('guardian-1'),
        signInSession: _session('guardian-1'),
      );
      await _pumpAppToGate(tester, repository: repository, auth: auth);

      await tester.tap(find.byKey(guardianPinForgotKey));
      await tester.pumpAndSettle();
      expect(find.byKey(guardianReauthSheetKey), findsOneWidget);

      await tester.tap(find.byKey(guardianReauthCancelKey));
      await tester.pumpAndSettle();

      expect(auth.signInCalls, 0);
      expect(repository.resetCalls, 0);
      expect(find.text('보호자 확인'), findsOneWidget);
    });
  });
}

Future<void> _pumpGate(
  WidgetTester tester, {
  required GuardianPinRepository repository,
  Future<bool> Function()? onReauthenticate,
  VoidCallback? onUnlocked,
  bool wireReauth = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GuardianPinGateScreen(
        repository: repository,
        onUnlocked: (_) => onUnlocked?.call(),
        onReauthenticate: wireReauth
            ? (_) async => await onReauthenticate?.call() ?? false
            : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 실제 앱 배선(재인증 시트 → 소셜 coordinator → 계정 대조)을 그대로 태운다.
Future<void> _pumpAppToGate(
  WidgetTester tester, {
  required GuardianPinRepository repository,
  required AuthRepository auth,
}) async {
  await tester.pumpWidget(
    DodamApp(
      initialRoute: AppRoutes.authBootstrap,
      authRepository: auth,
      guardianPinRepository: repository,
      guardianPinGateEnabled: true,
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('guardian-profile')));
  await tester.pumpAndSettle();
  expect(find.byKey(guardianPinGateKey), findsOneWidget);
}

Future<void> _reauthenticateWithKakao(WidgetTester tester) async {
  await tester.tap(find.byKey(guardianPinForgotKey));
  await tester.pumpAndSettle();
  expect(find.byKey(guardianReauthSheetKey), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
  await tester.pumpAndSettle();
}

Future<void> _submitPin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(guardianPinTextFieldKey), pin);
  await tester.pump();
  await tester.tap(find.byKey(guardianPinSubmitKey));
  await tester.pumpAndSettle();
}

AuthSession _session(String id) => AuthSession(
  user: AuthenticatedUser(
    id: id,
    provider: AuthProvider.kakao,
    providerUserId: 'provider-$id',
    role: UserRole.guardian,
    onboardingCompleted: true,
    email: '$id@example.com',
  ),
  tokens: AuthTokens(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
    accessTokenExpiresAt: DateTime(2030),
  ),
);

final class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    required this.restoredSession,
    required this.signInSession,
  });

  final AuthSession restoredSession;
  final AuthSession signInSession;
  int signInCalls = 0;

  @override
  Future<AuthSession?> restoreSession() async => restoredSession;

  @override
  Future<AuthSession> signIn(OAuthCredential credential) async {
    signInCalls += 1;
    return signInSession;
  }

  @override
  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input) =>
      throw UnimplementedError();

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

final class _ResetRepository implements GuardianPinRepository {
  _ResetRepository({
    this.pinConfigured = true,
    this.locked = false,
    this.retryAfterSeconds,
    this.resetError,
  });

  final bool pinConfigured;
  final bool locked;
  final int? retryAfterSeconds;
  final Object? resetError;

  bool _cleared = false;
  int resetCalls = 0;
  final List<String> verifiedPins = [];
  final List<String> configuredPins = [];

  @override
  Future<GuardianPinStatusDto> getStatus() async =>
      _status(configured: pinConfigured && !_cleared, locked: locked);

  @override
  Future<GuardianPinStatusDto> reset() async {
    resetCalls += 1;
    final error = resetError;
    if (error != null) throw error;
    _cleared = true;
    return _status(configured: false, locked: false);
  }

  @override
  Future<GuardianPinStatusDto> verify(String pin) async {
    verifiedPins.add(pin);
    return _status(configured: true, locked: false);
  }

  @override
  Future<GuardianPinStatusDto> configure(String pin) async {
    configuredPins.add(pin);
    _cleared = false;
    return _status(configured: true, locked: false);
  }

  GuardianPinStatusDto _status({
    required bool configured,
    required bool locked,
  }) => GuardianPinStatusDto(
    pinConfigured: configured,
    locked: locked,
    remainingAttempts: locked ? 0 : 5,
    retryAfterSeconds: locked ? retryAfterSeconds : null,
    lockedUntil: null,
    serverTime: DateTime.utc(2026, 8, 5),
  );

  @override
  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  }) => throw UnimplementedError();
}
