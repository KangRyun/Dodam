import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('보호자는 보호자 홈으로 이동한다', () {
    expect(
      AuthLandingResolver.resolve(UserRole.guardian),
      AuthLandingDestination.guardianHome,
    );
  });

  test('전문가와 관리자는 1차 MVP 미지원 화면으로 이동한다', () {
    expect(
      AuthLandingResolver.resolve(UserRole.expert),
      AuthLandingDestination.unsupportedRole,
    );
    expect(
      AuthLandingResolver.resolve(UserRole.admin),
      AuthLandingDestination.unsupportedRole,
    );
  });
}
