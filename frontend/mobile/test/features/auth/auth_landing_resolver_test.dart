import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('보호자는 프로필 선택 화면으로 이동한다', () {
    expect(
      AuthLandingResolver.resolve(UserRole.guardian),
      AuthLandingDestination.profileSelection,
    );
  });

  test('전문가는 바로 진입하고 관리자는 미지원 화면으로 이동한다', () {
    expect(
      AuthLandingResolver.resolve(UserRole.expert),
      AuthLandingDestination.expertProfile,
    );
    expect(
      AuthLandingResolver.resolve(UserRole.admin),
      AuthLandingDestination.unsupportedRole,
    );
  });
}
