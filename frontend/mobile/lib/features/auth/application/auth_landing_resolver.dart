import '../domain/enums/user_role.dart';

enum AuthLandingDestination { guardianHome, unsupportedRole }

abstract final class AuthLandingResolver {
  // 1차 MVP에서 지원하는 로그인 완료 목적지 결정
  static AuthLandingDestination resolve(UserRole role) =>
      role == UserRole.guardian
      ? AuthLandingDestination.guardianHome
      : AuthLandingDestination.unsupportedRole;
}
