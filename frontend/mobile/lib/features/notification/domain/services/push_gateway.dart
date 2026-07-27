import '../entities/push_message.dart';

/// 푸시 SDK(FCM)를 앱이 다루는 최소 형태로 감싼다.
///
/// SDK 타입이 도메인·조정 로직으로 새지 않게 하려는 경계다. 테스트는 이
/// 인터페이스만 대체하면 된다.
abstract interface class PushGateway {
  /// 현재 기기의 등록 Token이며 발급 실패 시 `null`이다.
  Future<String?> getToken();

  /// Token이 갱신될 때마다 새 값을 흘린다.
  Stream<String> get tokenRefreshes;

  /// 앱이 떠 있는 동안 도착한 메시지다.
  Stream<PushMessage> get foregroundMessages;

  /// 사용자가 알림을 눌러 앱이 열렸을 때의 메시지다.
  Stream<PushMessage> get openedMessages;

  /// 종료 상태에서 알림을 눌러 실행된 경우의 최초 메시지다.
  Future<PushMessage?> getInitialMessage();
}

/// 알림을 실제로 화면에 표시한다.
///
/// 계약(§0-1)상 `data`-only로 받으므로 OS 자동 표시가 없고 앱이 직접 띄운다.
abstract interface class PushPresenter {
  Future<void> initialize();

  Future<void> show(PushMessage message);

  /// 표시한 알림을 사용자가 누른 경우다.
  ///
  /// 이동은 화면 계층의 관심사라 표시자가 직접 처리하지 않고 흘려보낸다.
  Stream<PushMessage> get taps;
}
