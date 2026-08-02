import 'dart:async';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/notification/data/dto/notification_inbox_dtos.dart';
import 'package:dodam/features/notification/domain/entities/push_message.dart';
import 'package:dodam/features/notification/domain/repositories/notification_inbox_repository.dart';
import 'package:dodam/features/notification/domain/repositories/push_token_repository.dart';
import 'package:dodam/features/notification/domain/services/push_gateway.dart';
import 'package:dodam/features/notification/domain/services/push_permission_service.dart';
import 'package:dodam/features/notification/domain/services/push_setup.dart';
import 'package:dodam/features/notification/presentation/screens/notification_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 푸시 클릭이 실제 앱 조립(`DodamApp`)에서 화면을 어떻게 여는지 고정한다.
///
/// 매핑 함수는 `notification_route_resolver_test.dart`가, 판정기 자체는
/// `app_navigation_test.dart`가 본다. 여기서는 **배선**을 본다 —
/// `_openPushTarget`이 알림함 카드 탭과 같은 진입점을 지나는지(S15P11B209-501).
void main() {
  late _FakeGateway gateway;
  late _FakePresenter presenter;

  setUp(() {
    gateway = _FakeGateway();
    presenter = _FakePresenter();
  });

  tearDown(() {
    gateway.dispose();
    presenter.dispose();
  });

  /// 연결 자원이 없는 알림이다. 계약 §4.3상 알림함 목록으로 간다.
  PushMessage noResource(int notificationId) => PushMessage(
    notificationId: notificationId,
    type: 'RETENTION_NOTICE',
    title: '보관 기간 안내',
    content: '내용을 확인해 주세요',
  );

  testWidgets('연결 자원 없는 푸시를 알림함에서 또 눌러도 알림함이 겹쳐 쌓이지 않는다', (tester) async {
    await tester.pumpWidget(
      DodamApp(
        initialRoute: AppRoutes.authBootstrap,
        authRepository: _FakeAuthRepository(_guardianSession()),
        notificationInboxRepository: _EmptyNotificationInboxRepository(),
        pushSetup: PushSetup(
          gateway: gateway,
          presenter: presenter,
          tokenRepository: _NoopPushTokenRepository(),
          permissionService: _GrantedPushPermissionService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 세션 복원으로 푸시 구독이 시작됐어야 알림 클릭이 전달된다.
    expect(presenter.initialized, isTrue);

    gateway.emitOpened(noResource(900));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationListScreen, skipOffstage: false), findsOneWidget);

    // 알림함을 보고 있는 상태에서 또 다른 무자원 알림을 눌렀다.
    gateway.emitOpened(noResource(901));
    await tester.pumpAndSettle();

    // 카드 탭 경로는 같은 상황에서 이동하지 않는다. 푸시도 같아야 한다.
    expect(find.byType(NotificationListScreen, skipOffstage: false), findsOneWidget);
  });
}

AuthSession _guardianSession() => AuthSession(
  user: const AuthenticatedUser(
    id: 'guardian-1',
    provider: AuthProvider.kakao,
    providerUserId: 'provider-guardian-1',
    role: UserRole.guardian,
    onboardingCompleted: true,
    email: 'guardian@example.com',
  ),
  tokens: AuthTokens(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
    accessTokenExpiresAt: DateTime(2030),
  ),
);

final class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.restoredSession);

  final AuthSession? restoredSession;

  @override
  Future<AuthSession?> restoreSession() async => restoredSession;

  @override
  Future<AuthSession> signIn(OAuthCredential credential) =>
      throw UnimplementedError();

  @override
  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input) =>
      throw UnimplementedError();

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

final class _EmptyNotificationInboxRepository
    implements NotificationInboxRepository {
  @override
  Future<NotificationPage> getNotifications({
    NotificationFilterDto filter = const NotificationFilterDto(),
  }) async => const ApiPage(
    content: [],
    page: 0,
    size: 20,
    totalElements: 0,
    totalPages: 0,
    hasNext: false,
  );

  @override
  Future<NotificationReadDto> markRead(int notificationId) =>
      throw UnimplementedError();

  @override
  Future<NotificationReadAllDto> markAllRead({String? type}) =>
      throw UnimplementedError();
}

final class _FakeGateway implements PushGateway {
  final _tokenRefreshes = StreamController<String>.broadcast();
  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();

  void emitOpened(PushMessage value) => _opened.add(value);

  void dispose() {
    _tokenRefreshes.close();
    _foreground.close();
    _opened.close();
  }

  @override
  Future<String?> getToken() async => 'fcm-token';

  @override
  Stream<String> get tokenRefreshes => _tokenRefreshes.stream;

  @override
  Stream<PushMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => _opened.stream;

  @override
  Future<PushMessage?> getInitialMessage() async => null;
}

final class _FakePresenter implements PushPresenter {
  final _taps = StreamController<PushMessage>.broadcast();
  bool initialized = false;

  void dispose() => _taps.close();

  @override
  Stream<PushMessage> get taps => _taps.stream;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> show(PushMessage message) async {}
}

final class _NoopPushTokenRepository implements PushTokenRepository {
  @override
  Future<void> register(String pushToken) async {}

  @override
  Future<void> unregister() async {}
}

final class _GrantedPushPermissionService implements PushPermissionService {
  @override
  Future<PushPermissionStatus> request() async => PushPermissionStatus.granted;

  @override
  Future<bool> openSettings() async => true;
}
