import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ChildHomeIntroStore {
  Future<bool> hasSeen(int childId);
  Future<void> markSeen(int childId);
}

final class SecureChildHomeIntroStore implements ChildHomeIntroStore {
  SecureChildHomeIntroStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(int childId) => 'child_home_character_intro_seen:$childId';

  @override
  Future<bool> hasSeen(int childId) async {
    try {
      return await _storage.read(key: _key(childId)) == 'true';
    } on Object {
      // 저장소를 읽지 못하면 매 진입마다 방해하지 않도록 이번 실행에서는 본 것으로 둔다.
      return true;
    }
  }

  @override
  Future<void> markSeen(int childId) async {
    await _storage.write(key: _key(childId), value: 'true');
  }
}
