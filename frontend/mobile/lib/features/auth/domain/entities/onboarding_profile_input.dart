import '../enums/user_role.dart';

// 신규 사용자 기본 정보
final class OnboardingProfileInput {
  const OnboardingProfileInput({required this.role, required this.nickname});

  final UserRole role;
  final String nickname;
}
