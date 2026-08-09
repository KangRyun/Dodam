import '../domain/enums/user_role.dart';

enum AuthLandingDestination { profileSelection, expertProfile, unsupportedRole }

abstract final class AuthLandingResolver {
  // 로그인 계정 역할에 따라 프로필 진입 방식을 결정
  static AuthLandingDestination resolve(UserRole? role) => switch (role) {
    UserRole.guardian => AuthLandingDestination.profileSelection,
    UserRole.expert => AuthLandingDestination.expertProfile,
    _ => AuthLandingDestination.unsupportedRole,
  };
}
