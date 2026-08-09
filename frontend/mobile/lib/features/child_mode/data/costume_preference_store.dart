import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 아동이 고른 도담이 코스튬을 기기에 로컬 저장한다(S15P11B209-750).
///
/// 아동별로 따로 기억하며, 저장/복원이 실패해도 홈 진입을 막지 않도록 오류는
/// 조용히 삼키고 기본 코스튬으로 되돌아간다(위젯 테스트의 플랫폼 채널 부재 포함).
final class CostumePreferenceStore {
  CostumePreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(int childId) => 'dodam.child.$childId.costume';

  Future<String?> read(int childId) async {
    try {
      return await _storage.read(key: _key(childId));
    } on Object {
      return null;
    }
  }

  Future<void> write(int childId, String code) async {
    try {
      await _storage.write(key: _key(childId), value: code);
    } on Object {
      // 로컬 저장 실패는 무시한다 — 다음 진입 시 기본 코스튬으로 시작한다.
    }
  }
}
