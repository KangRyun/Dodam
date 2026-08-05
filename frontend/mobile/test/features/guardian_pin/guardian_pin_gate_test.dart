import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/state/guardian_unlock_controller.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/guardian_pin/data/dto/guardian_pin_dtos.dart';
import 'package:dodam/features/guardian_pin/domain/failures/guardian_pin_failure.dart';
import 'package:dodam/features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import 'package:dodam/features/guardian_pin/presentation/screens/guardian_pin_gate_screen.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_pin_input.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_pin_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보호자 홈 진입 PIN gate(S15P11B209-874).
///
/// gate는 `/guardian/home` 라우트 생성 지점 한 곳에 있다. 보호자 전환 경로 넷은
/// 모두 이 라우트로 모이므로, 여기서 막히면 넷 다 막힌다.
void main() {
  testWidgets('flag가 켜진 cold start는 보호자 홈 대신 PIN 확인 화면을 연다', (tester) async {
    final repository = _GateRepository();
    await _pumpApp(tester, repository: repository);

    expect(find.byKey(guardianPinGateKey), findsOneWidget);
    expect(find.text('보호자 확인'), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
    expect(repository.statusCalls, 1);
  });

  testWidgets('PIN 확인에 성공하면 보호자 홈으로 들어간다', (tester) async {
    final repository = _GateRepository();
    await _pumpApp(tester, repository: repository);
    await _submitPin(tester, '1234');

    expect(repository.verifiedPins, ['1234']);
    expect(find.byKey(guardianPinGateKey), findsNothing);
    expect(find.text('보호자 홈'), findsWidgets);
  });

  testWidgets('PIN이 없는 계정은 확인이 아니라 설정 흐름으로 시작한다', (tester) async {
    final repository = _GateRepository(pinConfigured: false);
    await _pumpApp(tester, repository: repository);

    expect(find.text('보호자 PIN 설정'), findsOneWidget);
    expect(find.text('사용할 숫자 4자리를 입력해 주세요.'), findsOneWidget);

    // 새 PIN → 확인 입력 두 단계를 거쳐야 설정이 끝난다.
    await _submitPin(tester, '2468');
    expect(find.text('같은 PIN을 한 번 더 입력해 주세요.'), findsOneWidget);
    await _submitPin(tester, '2468');

    expect(repository.configuredPins, ['2468']);
    expect(repository.verifiedPins, isEmpty);
    expect(find.byKey(guardianPinGateKey), findsNothing);
    expect(find.text('보호자 홈'), findsWidgets);
  });

  testWidgets('서버가 잠금이라고 하면 그 안내만 보여주고 FE는 시간을 세지 않는다', (tester) async {
    final repository = _GateRepository(locked: true, retryAfterSeconds: 45);
    await _pumpApp(tester, repository: repository);

    expect(find.textContaining('45초'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(guardianPinTextFieldKey)).enabled,
      isFalse,
    );
    // 잠금 해제 판정은 서버 재조회로만 한다 — 화면에는 카운트다운이 없다.
    expect(
      tester.widget<AppButton>(find.byKey(guardianPinSubmitKey)).label,
      '상태 다시 확인',
    );

    await tester.pump(const Duration(seconds: 90));
    expect(find.textContaining('45초'), findsOneWidget);
    expect(repository.statusCalls, 1);
    expect(find.byKey(guardianPinGateKey), findsOneWidget);
  });

  testWidgets('PIN_UNAVAILABLE(503)에도 gate는 열리지 않고 오류만 보여준다', (tester) async {
    final repository = _GateRepository(
      statusError: const GuardianPinFailure(
        type: GuardianPinFailureType.unavailable,
        code: 'PIN_UNAVAILABLE',
      ),
    );
    await _pumpApp(tester, repository: repository);

    expect(find.textContaining('지금은 PIN 기능을 사용할 수 없어요'), findsOneWidget);
    expect(find.byKey(guardianPinGateKey), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
  });

  testWidgets('프로필 선택에서 보호자를 눌러도 gate를 지난다', (tester) async {
    final repository = _GateRepository();
    await _pumpApp(
      tester,
      repository: repository,
      initialRoute: AppRoutes.profileSelection,
    );

    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(guardianPinGateKey), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
  });

  testWidgets('백그라운드로 갔다 오면 보호자 화면은 다시 잠긴다', (tester) async {
    final repository = _GateRepository();
    await _pumpApp(tester, repository: repository);
    await _submitPin(tester, '1234');
    expect(find.text('보호자 홈'), findsWidgets);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(guardianPinGateKey), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
    expect(repository.statusCalls, 2);
  });

  testWidgets('보호자 홈 위에 쌓인 화면에서 백그라운드로 가도 gate로 되돌린다', (tester) async {
    // 잠금만 걸면 이미 떠 있는 보호자 화면이 그대로 남는다. 홈 위에 쌓인 화면도
    // 같은 보호자 영역이라 함께 되돌려야 한다.
    final repository = _GateRepository();
    await _pumpApp(
      tester,
      repository: repository,
      initialRoute: AppRoutes.profileSelection,
    );
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();
    await _submitPin(tester, '1234');

    await tester.tap(find.byKey(const ValueKey('guardian-switch-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-selection-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-guardian-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(guardianPinGateKey), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(guardianPinGateKey), findsOneWidget);
  });

  testWidgets('아동 모드에 들어갔다 보호자로 돌아오면 다시 잠긴다', (tester) async {
    final repository = _GateRepository();
    await _pumpApp(
      tester,
      repository: repository,
      initialRoute: AppRoutes.profileSelection,
    );

    // 보호자로 한 번 들어가 잠금을 풀어 둔다.
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();
    await _submitPin(tester, '1234');
    expect(find.text('보호자 홈'), findsWidgets);

    // 프로필 전환 → 아동 모드 진입.
    await tester.tap(find.byKey(const ValueKey('guardian-switch-profile')));
    await tester.pumpAndSettle();
    final childProfile = find.byKey(const ValueKey('child-profile-3'));
    await tester.ensureVisible(childProfile);
    await tester.tap(childProfile);
    await tester.pumpAndSettle();
    expect(find.text('도담이, 오늘은 무엇을 그려 볼까?'), findsOneWidget);

    // 길게 눌러 보호자 복귀 — 아이가 쓰던 기기라 PIN을 다시 묻는다.
    await tester.longPress(find.byKey(const ValueKey('guardian-return-hold')));
    await tester.pumpAndSettle();

    expect(find.byKey(guardianPinGateKey), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
  });

  testWidgets('flag가 꺼진 기본 구성에서는 gate가 서지 않는다', (tester) async {
    final repository = _GateRepository();
    await tester.pumpWidget(DodamApp(guardianPinRepository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(guardianPinGateKey), findsNothing);
    expect(find.text('보호자 홈'), findsWidgets);
    expect(repository.statusCalls, 0);
  });

  testWidgets('라우터는 보호자 홈 라우트 하나에서만 gate를 세운다', (tester) async {
    final unlock = GuardianUnlockController();
    addTearDown(unlock.dispose);
    final repository = _GateRepository();

    // 호출자가 누구든(프로필 선택·활동 완료·아동 복귀·오류 재시도) 보호자 홈은 이
    // 라우트를 지난다. 라우트 생성 지점만 검사하면 네 경로를 한 번에 덮는다.
    Future<void> pumpRoute(String route) async {
      await tester.pumpWidget(
        MaterialApp(
          // 키를 바꿔 Navigator를 새로 만들어야 initialRoute가 다시 적용된다.
          key: ValueKey(route),
          initialRoute: route,
          onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
            settings,
            guardianUnlock: unlock,
            guardianPinRepository: repository,
            guardianPinGateEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpRoute(AppRoutes.guardianHome);
    expect(find.byType(GuardianPinGateScreen), findsOneWidget);

    await pumpRoute(AppRoutes.profileSelection);
    expect(find.byType(GuardianPinGateScreen), findsNothing);

    await pumpRoute(AppRoutes.childModeHome('3'));
    expect(find.byType(GuardianPinGateScreen), findsNothing);

    unlock.unlock();
    await pumpRoute(AppRoutes.guardianHome);
    expect(find.byType(GuardianPinGateScreen), findsNothing);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required GuardianPinRepository repository,
  String initialRoute = AppRoutes.guardianHome,
}) async {
  await tester.pumpWidget(
    DodamApp(
      guardianPinRepository: repository,
      guardianPinGateEnabled: true,
      initialRoute: initialRoute,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitPin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(guardianPinTextFieldKey), pin);
  await tester.pump();
  await tester.tap(find.byKey(guardianPinSubmitKey));
  await tester.pumpAndSettle();
}

final class _GateRepository implements GuardianPinRepository {
  _GateRepository({
    this.pinConfigured = true,
    this.locked = false,
    this.retryAfterSeconds,
    this.statusError,
  });

  final bool pinConfigured;
  final bool locked;
  final int? retryAfterSeconds;
  final Object? statusError;

  int statusCalls = 0;
  final List<String> verifiedPins = [];
  final List<String> configuredPins = [];

  @override
  Future<GuardianPinStatusDto> getStatus() async {
    statusCalls += 1;
    final error = statusError;
    if (error != null) throw error;
    return _status(configured: pinConfigured, locked: locked);
  }

  @override
  Future<GuardianPinStatusDto> verify(String pin) async {
    verifiedPins.add(pin);
    return _status(configured: true, locked: false);
  }

  @override
  Future<GuardianPinStatusDto> configure(String pin) async {
    configuredPins.add(pin);
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

  @override
  Future<GuardianPinStatusDto> reset() => throw UnimplementedError();
}
