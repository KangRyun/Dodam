/// Refresh Token 세션을 앱 설치 단위로 구분하는 식별자를 제공한다.
abstract interface class DeviceIdProvider {
  Future<String> getDeviceId();
}
