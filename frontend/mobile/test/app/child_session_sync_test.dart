import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('인증 세션이 없으면 아동 목록을 조회하지 않는다', (tester) async {
    final authRepository = _FakeAuthRepository();
    final childRepository = _TrackingChildRepository(
      canRequest: () => authRepository.sessionReady,
    );

    await tester.pumpWidget(
      DodamApp(
        initialRoute: AppRoutes.authBootstrap,
        authRepository: authRepository,
        childRepository: childRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(childRepository.getChildrenCalls, 0);
    expect(find.byKey(const ValueKey('social-login-kakao')), findsOneWidget);
  });

  testWidgets('저장된 보호자 세션을 복원한 뒤 빈 아동 목록을 조회한다', (tester) async {
    final authRepository = _FakeAuthRepository(restoredSession: _session());
    final childRepository = _TrackingChildRepository(
      canRequest: () => authRepository.sessionReady,
    );

    await tester.pumpWidget(
      DodamApp(
        initialRoute: AppRoutes.authBootstrap,
        authRepository: authRepository,
        childRepository: childRepository,
      ),
    );
    await tester.pumpAndSettle();

    // 복원 후 프로필 선택 화면 → 보호자 선택
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();

    expect(childRepository.getChildrenCalls, 1);
    expect(find.byKey(const ValueKey('child-list-empty')), findsOneWidget);
  });

  testWidgets('기존 보호자 로그인 후 아동 목록을 조회한다', (tester) async {
    final authRepository = _FakeAuthRepository(signInSession: _session());
    final childRepository = _TrackingChildRepository(
      canRequest: () => authRepository.sessionReady,
      children: const [_child],
    );

    await tester.pumpWidget(
      DodamApp(
        initialRoute: AppRoutes.authBootstrap,
        authRepository: authRepository,
        childRepository: childRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pumpAndSettle();

    // 로그인 후 프로필 선택 화면 → 보호자 선택
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();

    expect(childRepository.getChildrenCalls, 1);
    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
  });

  testWidgets('신규 보호자 onboarding 완료 후 아동 목록을 조회한다', (tester) async {
    final authRepository = _FakeAuthRepository(
      signInSession: _session(onboardingCompleted: false),
      onboardingSession: _session(),
    );
    final childRepository = _TrackingChildRepository(
      canRequest: () => authRepository.sessionReady,
    );

    await tester.pumpWidget(
      DodamApp(
        initialRoute: AppRoutes.authBootstrap,
        authRepository: authRepository,
        childRepository: childRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('onboarding-role-guardian-tap')),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), '보호자');
    final profileNext = find.byKey(const ValueKey('onboarding-profile-next'));
    await tester.ensureVisible(profileNext);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: profileNext, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    final consentSubmit = find.byKey(const ValueKey('consent-submit'));
    await tester.ensureVisible(consentSubmit);
    await tester.tap(
      find.descendant(of: consentSubmit, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    // 온보딩 완료 후 프로필 선택 화면 → 보호자 선택
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();

    expect(childRepository.getChildrenCalls, 1);
    expect(find.byKey(const ValueKey('child-list-empty')), findsOneWidget);
  });
}

AuthSession _session({bool onboardingCompleted = true}) => AuthSession(
  user: AuthenticatedUser(
    id: 'guardian-1',
    provider: AuthProvider.kakao,
    providerUserId: 'provider-guardian-1',
    role: UserRole.guardian,
    onboardingCompleted: onboardingCompleted,
    email: 'guardian@example.com',
  ),
  tokens: AuthTokens(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
    accessTokenExpiresAt: DateTime(2030),
  ),
);

const _child = ChildSummaryDto(
  childId: 3,
  nickname: '도담이',
  birthDate: '2019-03-14',
  age: 7,
  profileImageUrl: null,
  preferredCharacter: 'BEAR',
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'COMPLETED',
  relationshipType: 'MOTHER',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

final class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.restoredSession,
    this.signInSession,
    this.onboardingSession,
  });

  final AuthSession? restoredSession;
  final AuthSession? signInSession;
  final AuthSession? onboardingSession;
  bool sessionReady = false;

  @override
  Future<AuthSession> signIn(OAuthCredential credential) async {
    final session = signInSession ?? _session();
    sessionReady = true;
    return session;
  }

  @override
  Future<AuthSession?> restoreSession() async {
    sessionReady = restoredSession != null;
    return restoredSession;
  }

  @override
  Future<AuthSession> completeOnboarding(NewUserOnboardingInput input) async {
    final session = onboardingSession ?? _session();
    sessionReady = true;
    return session;
  }

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    sessionReady = false;
  }
}

final class _TrackingChildRepository implements ChildRepository {
  _TrackingChildRepository({
    required this.canRequest,
    this.children = const [],
  });

  final bool Function() canRequest;
  final List<ChildSummaryDto> children;
  int getChildrenCalls = 0;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCalls += 1;
    if (!canRequest()) {
      throw StateError('인증 전 아동 목록 요청');
    }
    return children;
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();

  @override
  Future<void> deleteChild(int childId, {bool cascade = true}) =>
      throw UnimplementedError();

  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}
