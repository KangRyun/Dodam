import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('인증 세션을 보안 저장소에 저장하고 다시 복원한다', () async {
    final store = SecureAuthSessionStore();
    final session = _session();

    await store.save(session);

    final restored = await store.read();
    expect(restored?.user, session.user);
    expect(restored?.tokens, session.tokens);
  });

  test('로그아웃 시 보안 저장소의 인증 세션을 제거한다', () async {
    final store = SecureAuthSessionStore();
    await store.save(_session());

    await store.clear();

    expect(await store.read(), isNull);
  });
}

AuthSession _session() => AuthSession(
  user: const AuthenticatedUser(
    id: 'guardian-1',
    provider: AuthProvider.kakao,
    providerUserId: 'provider-1',
    role: UserRole.guardian,
    onboardingCompleted: true,
    email: 'guardian@dodam.test',
    nickname: '민지엄마',
  ),
  tokens: AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: DateTime(2026, 7, 24),
  ),
);
