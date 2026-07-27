import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/push_message.dart';
import '../../domain/services/push_gateway.dart';

/// `data`-only 메시지를 받아 앱이 직접 알림을 띄운다.
///
/// OS 자동 표시를 쓰지 않으므로(계약 §0-1) 표시 시점·문구·아동 모드 차단을
/// 앱이 통제한다.
final class LocalPushPresenter implements PushPresenter {
  factory LocalPushPresenter({FlutterLocalNotificationsPlugin? plugin}) =>
      LocalPushPresenter._(plugin ?? FlutterLocalNotificationsPlugin());

  LocalPushPresenter._(this._plugin);

  /// 보호자 알림 채널이다. 아동 활동과 무관한 보호자 모드 전용이다.
  static const _channelId = 'dodam_guardian';
  static const _channelName = '보호자 알림';
  static const _channelDescription = '분석 완료·약관 변경 등 보호자에게 보내는 알림이에요.';

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<PushMessage>.broadcast();

  @override
  Stream<PushMessage> get taps => _taps.stream;

  /// 배경 격리(isolate)에서 1회성으로 쓴 뒤 정리할 때 호출한다.
  Future<void> dispose() => _taps.close();

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );
  }

  @override
  Future<void> show(PushMessage message) => _plugin.show(
    id: message.notificationId,
    title: message.title,
    body: message.content,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
    payload: _encode(message),
  );

  void _handleResponse(NotificationResponse response) {
    final message = _decode(response.payload);
    if (message != null) _taps.add(message);
  }

  /// 탭 시 라우팅에 필요한 값만 payload로 싣는다. 표시 문구는 다시 쓰지 않는다.
  static String _encode(PushMessage message) => [
    message.notificationId,
    message.type,
    message.resourceType?.wireValue ?? '',
    message.resourceId?.toString() ?? '',
  ].join('|');

  static PushMessage? _decode(String? payload) {
    if (payload == null) return null;

    final parts = payload.split('|');
    if (parts.length != 4) return null;

    final notificationId = int.tryParse(parts[0]);
    if (notificationId == null) return null;

    final resourceType = PushResourceType.tryParse(parts[2]);
    final resourceId = int.tryParse(parts[3]);
    final paired = resourceType != null && resourceId != null;

    return PushMessage(
      notificationId: notificationId,
      type: parts[1],
      title: '',
      content: '',
      resourceType: paired ? resourceType : null,
      resourceId: paired ? resourceId : null,
    );
  }
}
