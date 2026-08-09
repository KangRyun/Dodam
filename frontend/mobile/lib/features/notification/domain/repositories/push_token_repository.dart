/// 푸시 디바이스 Token을 서버에 등록·해제한다.
///
/// 등록은 `(userId, deviceId)` upsert라 갱신도 같은 호출을 쓴다. 해제는 행
/// 삭제가 아니라 비활성화이며 재로그인하면 다시 활성화된다
/// (`docs/api/notification-inbox-contract.md` §3·§4).
abstract interface class PushTokenRepository {
  /// FCM 등록 Token을 서버에 등록하거나 갱신한다.
  Future<void> register(String pushToken);

  /// 현재 기기의 Token을 비활성화한다. 로그아웃 시 호출한다.
  Future<void> unregister();
}
