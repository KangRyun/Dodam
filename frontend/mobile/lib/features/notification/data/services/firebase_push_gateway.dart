import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/entities/push_message.dart';
import '../../domain/services/push_gateway.dart';

/// FCM SDK를 [PushGateway] 형태로 감싼다.
///
/// 계약(§3)을 벗어난 메시지는 [PushMessage.tryParse]가 `null`을 주므로 스트림에서
/// 걸러 낸다. 잘못된 페이로드로 화면을 띄우지 않기 위한 fail-closed다.
final class FirebasePushGateway implements PushGateway {
  factory FirebasePushGateway({FirebaseMessaging? messaging}) =>
      FirebasePushGateway._(messaging ?? FirebaseMessaging.instance);

  FirebasePushGateway._(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage.transform(_parsed);

  @override
  Stream<PushMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.transform(_parsed);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushMessage.tryParse(message.data);
  }

  static final _parsed = StreamTransformer<RemoteMessage, PushMessage>.fromHandlers(
    handleData: (message, sink) {
      final parsed = PushMessage.tryParse(message.data);
      if (parsed != null) sink.add(parsed);
    },
  );
}
