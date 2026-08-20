import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_navigation.dart';
import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/state/guardian_unlock_controller.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/conversation/domain/services/microphone_permission_service.dart';
import 'package:dodam/features/drawing/domain/photo_permission_service.dart';
import 'package:dodam/features/guardian_pin/data/dto/guardian_pin_dtos.dart';
import 'package:dodam/features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import 'package:dodam/features/guardian_pin/presentation/screens/guardian_pin_gate_screen.dart';
import 'package:dodam/features/notification/domain/services/push_permission_service.dart';
import 'package:dodam/features/permission/permission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/reduced_motion.dart';

/// 로그인 직후 한 번만 세우는 권한 안내.
///
/// 화면은 보호자 착지점(프로필 선택·보호자 홈) **앞**에 선다. 보호자 홈 라우트에
/// 걸면 PIN gate와 같은 자리를 다투므로, 안내는 그 앞에서 끝나고 원래 목적지로
/// 이어 준다 — gate는 이어진 이동이 라우트를 다시 만들 때 그대로 선다.
void main() {
  useReducedMotionForTests();

  testWidgets('로그인을 마치면 권한 안내가 뜬다', (tester) async {
    final permissions = _Permissions();
    await _login(tester, permissions: permissions);

    expect(find.byKey(permissionOnboardingKey), findsOneWidget);
    expect(find.text('시작하기 전에 잠깐요'), findsOneWidget);
    expect(find.text('마이크'), findsOneWidget);
    expect(find.text('카메라'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    // 아직 프로필 선택으로 넘어가지 않았고, 권한도 묻지 않았다.
    expect(find.text('누가 도담이와 함께할까요?'), findsNothing);
    expect(permissions.microphone.requests, 0);
  });

  testWidgets('"나중에"는 아무 권한도 요청하지 않고 프로필 선택으로 넘어간다', (tester) async {
    final permissions = _Permissions();
    await _login(tester, permissions: permissions);

    await tester.tap(find.byKey(permissionOnboardingSkipKey));
    await tester.pumpAndSettle();

    expect(find.byKey(permissionOnboardingKey), findsNothing);
    expect(find.text('누가 도담이와 함께할까요?'), findsOneWidget);
    expect(permissions.microphone.requests, 0);
    expect(permissions.photo.requested, isEmpty);
    expect(permissions.push.requests, 0);
    // 건너뛴 것도 응답이다 — 다시 묻지 않는다.
    expect(permissions.store.answered, isTrue);
  });

  testWidgets('"모두 허용"은 마이크·카메라·알림 세 서비스를 모두 부른다', (tester) async {
    final permissions = _Permissions();
    await _login(tester, permissions: permissions);

    await tester.tap(find.byKey(permissionOnboardingAllowAllKey));
    await tester.pumpAndSettle();

    expect(permissions.microphone.requests, 1);
    // 갤러리(photos)는 시스템 사진 선택기가 권한 없이 처리하고 매니페스트가 앞당겨
    // 선언한 것도 카메라뿐이라, 여기서는 카메라만 묻는다.
    expect(permissions.photo.requested, [PhotoPermissionKind.camera]);
    expect(permissions.push.requests, 1);
    expect(find.text('누가 도담이와 함께할까요?'), findsOneWidget);
    expect(permissions.store.answered, isTrue);
  });

  testWidgets('거부하거나 요청이 실패해도 앱은 그대로 진행된다', (tester) async {
    // 마이크 요청은 아예 실패하고 나머지는 거부된 상황. 이 화면은 앞당겨 묻는
    // 장치일 뿐이라 어느 쪽도 진행을 막지 않아야 한다.
    final permissions = _Permissions(
      microphoneError: StateError('권한 플러그인 없음'),
      photoResult: PhotoPermissionStatus.permanentlyDenied,
      pushResult: PushPermissionStatus.denied,
    );
    await _login(tester, permissions: permissions);

    await tester.tap(find.byKey(permissionOnboardingAllowAllKey));
    await tester.pumpAndSettle();

    // 하나가 실패해도 나머지는 계속 묻는다.
    expect(permissions.photo.requested, [PhotoPermissionKind.camera]);
    expect(permissions.push.requests, 1);
    expect(find.byKey(permissionOnboardingKey), findsNothing);
    expect(find.text('누가 도담이와 함께할까요?'), findsOneWidget);
  });

  testWidgets('한 번 응답하면 앱을 다시 켜도 뜨지 않는다', (tester) async {
    final store = _MemoryStore();
    await _login(tester, permissions: _Permissions(store: store));
    await tester.tap(find.byKey(permissionOnboardingSkipKey));
    await tester.pumpAndSettle();

    // 앱을 다시 켠다 — 저장된 세션으로 들어오는 cold start 경로.
    await tester.pumpWidget(
      DodamApp(
        key: const ValueKey('relaunch'),
        authRepository: _GuardianAuthRepository(),
        permissionOnboarding: _Permissions(store: store).controller,
        initialRoute: AppRoutes.authBootstrap,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(permissionOnboardingKey), findsNothing);
    expect(find.text('누가 도담이와 함께할까요?'), findsOneWidget);
  });

  testWidgets('권한 안내는 보호자 홈 PIN gate를 대신하지 않는다', (tester) async {
    final permissions = _Permissions();
    await _login(
      tester,
      permissions: permissions,
      pinRepository: _GatePinRepository(),
      pinGateEnabled: true,
    );

    // 안내가 먼저 선다. 이 시점에는 아직 보호자 홈에 닿지 않았으므로 gate도 없다.
    expect(find.byKey(permissionOnboardingKey), findsOneWidget);
    expect(find.byKey(guardianPinGateKey), findsNothing);

    await tester.tap(find.byKey(permissionOnboardingSkipKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();

    // 보호자 홈으로 가는 길에서 gate는 그대로 선다.
    expect(find.byKey(guardianPinGateKey), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
  });

  testWidgets('안내가 끝나면 원래 가려던 보호자 홈으로 이어지고 거기서 gate를 만난다', (tester) async {
    // 온보딩을 막 끝낸 보호자는 프로필 선택이 아니라 보호자 홈으로 간다. 안내가
    // 그 차이를 지우지 않는지, 그리고 이어진 이동이 gate를 지나는지 확인한다.
    final permissions = _Permissions();
    await permissions.controller.load();
    final unlock = GuardianUnlockController();
    addTearDown(unlock.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        initialRoute: AppRoutes.expertProfile,
        onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
          settings,
          permissionOnboarding: permissions.controller,
          guardianUnlock: unlock,
          guardianPinRepository: _GatePinRepository(),
          guardianPinGateEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    AppNavigation.resetToOn(
      navigatorKey.currentState!,
      AppRoutes.permissionOnboarding,
      arguments: const PermissionOnboardingRouteArguments(
        nextRoute: AppRoutes.guardianHome,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(permissionOnboardingKey), findsOneWidget);

    await tester.tap(find.byKey(permissionOnboardingSkipKey));
    await tester.pumpAndSettle();

    expect(find.byType(GuardianPinGateScreen), findsOneWidget);
    expect(find.text('보호자 홈'), findsNothing);
  });

  testWidgets('안내를 주입하지 않은 구성은 기존 로그인 흐름 그대로다', (tester) async {
    await tester.pumpWidget(
      DodamApp(
        authRepository: _GuardianAuthRepository(),
        initialRoute: AppRoutes.login,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pumpAndSettle();

    expect(find.byKey(permissionOnboardingKey), findsNothing);
    expect(find.text('누가 도담이와 함께할까요?'), findsOneWidget);
  });

  // 앱은 가로 고정이라 세로 공간이 좁다(S15P11B209-878). 큰 글자까지 겹치면 본문이
  // 넘치기 쉬워, 두 버튼은 늘 화면에 남고 본문만 스크롤로 물러나는지 확인한다.
  final viewports = <({Size size, double textScale})>[
    (size: const Size(844, 390), textScale: 1),
    (size: const Size(844, 390), textScale: 2),
    (size: const Size(390, 844), textScale: 2),
    (size: const Size(1280, 800), textScale: 1),
  ];

  for (final viewport in viewports) {
    testWidgets('${viewport.size} textScale ${viewport.textScale}에서 넘치지 않는다', (
      tester,
    ) async {
      final permissions = _Permissions();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.size;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: viewport.size,
              textScaler: TextScaler.linear(viewport.textScale),
            ),
            child: PermissionOnboardingScreen(
              controller: permissions.controller,
              onFinished: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byKey(permissionOnboardingAllowAllKey), findsOneWidget);
      expect(find.byKey(permissionOnboardingSkipKey), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -180),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  group('PermissionOnboardingController', () {
    test('읽기 전에는 안내를 세우지 않는다', () {
      expect(_Permissions().controller.isPending, isFalse);
    });

    test('저장소 읽기가 실패하면 아직 안 물어본 것으로 본다', () async {
      final permissions = _Permissions(store: _MemoryStore(readError: true));
      await permissions.controller.load();

      // 잘못 보여 주면 한 번 더 뜨는 것으로 끝나지만, 잘못 숨기면 기능이 조용히
      // 사라진다.
      expect(permissions.controller.isPending, isTrue);
    });

    test('저장에 실패해도 이번 실행에서는 다시 묻지 않는다', () async {
      final permissions = _Permissions(store: _MemoryStore(writeError: true));
      await permissions.controller.load();
      await permissions.controller.skip();

      expect(permissions.controller.isPending, isFalse);
      await permissions.controller.load();
      expect(permissions.controller.isPending, isFalse);
    });
  });
}

Future<void> _login(
  WidgetTester tester, {
  required _Permissions permissions,
  GuardianPinRepository? pinRepository,
  bool pinGateEnabled = false,
}) async {
  await tester.pumpWidget(
    DodamApp(
      authRepository: _GuardianAuthRepository(),
      permissionOnboarding: permissions.controller,
      guardianPinRepository: pinRepository,
      guardianPinGateEnabled: pinGateEnabled,
      initialRoute: AppRoutes.login,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
  await tester.pumpAndSettle();
}

/// 권한 안내가 쓰는 경계 넷(저장소 + 서비스 셋)을 한 번에 묶어 둔다.
final class _Permissions {
  _Permissions({
    _MemoryStore? store,
    Object? microphoneError,
    MicrophonePermissionStatus microphoneResult =
        MicrophonePermissionStatus.granted,
    PhotoPermissionStatus photoResult = PhotoPermissionStatus.granted,
    PushPermissionStatus pushResult = PushPermissionStatus.granted,
  }) : store = store ?? _MemoryStore(),
       microphone = _FakeMicrophone(microphoneResult, microphoneError),
       photo = _FakePhoto(photoResult),
       push = _FakePush(pushResult);

  final _MemoryStore store;
  final _FakeMicrophone microphone;
  final _FakePhoto photo;
  final _FakePush push;

  late final controller = PermissionOnboardingController(
    store: store,
    microphonePermissionService: microphone,
    photoPermissionService: photo,
    pushPermissionService: push,
  );
}

final class _MemoryStore implements PermissionOnboardingStore {
  _MemoryStore({this.readError = false, this.writeError = false});

  final bool readError;
  final bool writeError;
  bool answered = false;

  @override
  Future<bool> hasAnswered() async {
    if (readError) throw StateError('보안 저장소를 읽지 못했다');
    return answered;
  }

  @override
  Future<void> markAnswered() async {
    if (writeError) throw StateError('보안 저장소에 쓰지 못했다');
    answered = true;
  }
}

final class _FakeMicrophone implements MicrophonePermissionService {
  _FakeMicrophone(this._result, this._error);

  final MicrophonePermissionStatus _result;
  final Object? _error;
  int requests = 0;

  @override
  Future<MicrophonePermissionStatus> request() async {
    requests += 1;
    final error = _error;
    if (error != null) throw error;
    return _result;
  }

  @override
  Future<bool> openSettings() async => true;
}

final class _FakePhoto implements PhotoPermissionService {
  _FakePhoto(this._result);

  final PhotoPermissionStatus _result;
  final List<PhotoPermissionKind> requested = [];

  @override
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind) async =>
      _result;

  @override
  Future<PhotoPermissionStatus> request(PhotoPermissionKind kind) async {
    requested.add(kind);
    return _result;
  }

  @override
  Future<bool> openSettings() async => true;
}

final class _FakePush implements PushPermissionService {
  _FakePush(this._result);

  final PushPermissionStatus _result;
  int requests = 0;

  @override
  Future<PushPermissionStatus> request() async {
    requests += 1;
    return _result;
  }

  @override
  Future<bool> openSettings() async => true;
}

final class _GuardianAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> signIn(OAuthCredential credential) async => _session();

  @override
  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input) async =>
      _session();

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) async =>
      _session().tokens;

  @override
  Future<AuthSession?> restoreSession() async => _session();

  @override
  Future<void> signOut() async {}
}

AuthSession _session() => AuthSession(
  user: const AuthenticatedUser(
    id: 'guardian-1',
    provider: AuthProvider.kakao,
    providerUserId: 'kakao-1',
    role: UserRole.guardian,
    onboardingCompleted: true,
    email: 'guardian@dodam.test',
  ),
  // 만료 판정이 지금 시각을 보므로 고정 날짜를 쓰면 시간이 지나 부트스트랩이
  // 세션을 버린다.
  tokens: AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
  ),
);

final class _GatePinRepository implements GuardianPinRepository {
  @override
  Future<GuardianPinStatusDto> getStatus() async => _status();

  @override
  Future<GuardianPinStatusDto> verify(String pin) async => _status();

  @override
  Future<GuardianPinStatusDto> configure(String pin) async => _status();

  @override
  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  }) => throw UnimplementedError();

  @override
  Future<GuardianPinStatusDto> reset() => throw UnimplementedError();

  GuardianPinStatusDto _status() => GuardianPinStatusDto(
    pinConfigured: true,
    locked: false,
    remainingAttempts: 5,
    retryAfterSeconds: null,
    lockedUntil: null,
    serverTime: DateTime.now().toUtc(),
  );
}
