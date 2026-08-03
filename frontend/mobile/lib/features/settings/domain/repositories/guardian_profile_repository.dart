import '../../../auth/domain/entities/authenticated_user.dart';

/// USER-01/03 보호자 본인 정보 조회·수정 경계.
abstract interface class GuardianProfileRepository {
  Future<AuthenticatedUser> getCurrentUserProfile();

  Future<AuthenticatedUser> updateCurrentUserProfile({
    required String nickname,
  });
}
