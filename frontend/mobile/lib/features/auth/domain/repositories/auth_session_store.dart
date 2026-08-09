import '../entities/auth_session.dart';

abstract interface class AuthSessionStore {
  Future<void> save(AuthSession session);

  Future<AuthSession?> read();

  Future<void> clear();
}
