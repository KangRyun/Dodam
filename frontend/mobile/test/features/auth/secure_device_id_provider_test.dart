import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('설치 식별자를 최초 한 번 생성하고 보안 저장소에서 재사용한다', () async {
    final provider = SecureDeviceIdProvider();

    final generated = await provider.getDeviceId();
    final restored = await provider.getDeviceId();

    expect(generated, hasLength(43));
    expect(generated, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(restored, generated);
  });
}
