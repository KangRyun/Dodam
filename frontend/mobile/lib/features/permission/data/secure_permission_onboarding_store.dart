import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/permission_onboarding_store.dart';

/// OS 보안 저장소에 "권한 안내에 응답했다"를 남긴다.
///
/// 새 저장 의존성을 들이지 않으려고 앱이 이미 쓰는 `flutter_secure_storage`를
/// 그대로 쓴다 — `SecureDeviceIdProvider`(설치 식별자)와 같은 자리, 같은 수명이다.
/// 비밀은 아니지만 저장소를 하나로 모아 두는 편이 관리하기 쉽고, 앱을 지우면 함께
/// 사라져 재설치 시 다시 묻는다. 재설치하면 기기 권한도 초기화되므로 그 편이 맞다.
///
/// 로그아웃은 이 값을 지우지 않는다([PermissionOnboardingStore] 문서 참조 — 기기
/// 권한은 계정을 따라가지 않는다).
final class SecurePermissionOnboardingStore
    implements PermissionOnboardingStore {
  SecurePermissionOnboardingStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'dodam.permission.onboarding-answered';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> hasAnswered() async =>
      await _storage.read(key: _storageKey) == 'true';

  @override
  Future<void> markAnswered() =>
      _storage.write(key: _storageKey, value: 'true');
}
