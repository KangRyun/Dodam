import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/repositories/device_id_provider.dart';

/// 최초 요청에서 임의 설치 식별자를 생성하고 OS 보안 저장소에서 재사용한다.
final class SecureDeviceIdProvider implements DeviceIdProvider {
  SecureDeviceIdProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'dodam.auth.device-id';

  final FlutterSecureStorage _storage;

  @override
  Future<String> getDeviceId() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored != null && stored.isNotEmpty) return stored;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final generated = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: _storageKey, value: generated);
    return generated;
  }
}
