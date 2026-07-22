import '../enums/auth_provider.dart';
import '../enums/user_role.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.provider,
    required this.providerUserId,
    required this.role,
    required this.onboardingCompleted,
    this.email,
    this.nickname,
    this.profileImageUrl,
  });

  final String id;
  final AuthProvider provider;
  final String providerUserId;
  final UserRole role;
  final bool onboardingCompleted;
  final String? email;
  final String? nickname;
  final String? profileImageUrl;

  bool get needsEmail => email == null || email!.trim().isEmpty;

  AuthenticatedUser copyWith({
    String? id,
    AuthProvider? provider,
    String? providerUserId,
    UserRole? role,
    bool? onboardingCompleted,
    String? email,
    String? nickname,
    String? profileImageUrl,
  }) => AuthenticatedUser(
    id: id ?? this.id,
    provider: provider ?? this.provider,
    providerUserId: providerUserId ?? this.providerUserId,
    role: role ?? this.role,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    email: email ?? this.email,
    nickname: nickname ?? this.nickname,
    profileImageUrl: profileImageUrl ?? this.profileImageUrl,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthenticatedUser &&
          id == other.id &&
          provider == other.provider &&
          providerUserId == other.providerUserId &&
          role == other.role &&
          onboardingCompleted == other.onboardingCompleted &&
          email == other.email &&
          nickname == other.nickname &&
          profileImageUrl == other.profileImageUrl;

  @override
  int get hashCode => Object.hash(
    id,
    provider,
    providerUserId,
    role,
    onboardingCompleted,
    email,
    nickname,
    profileImageUrl,
  );
}
