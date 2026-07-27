enum PushPermissionStatus { granted, denied, permanentlyDenied }

/// 알림 표시 권한을 요청한다.
///
/// Android 13(API 33)+ 는 `POST_NOTIFICATIONS` 런타임 권한이 필요하다. 거부돼도
/// 앱 기능과 알림함은 정상 동작해야 한다
/// (`docs/api/push-notification-delivery-contract.md` §4.2).
abstract interface class PushPermissionService {
  Future<PushPermissionStatus> request();

  Future<bool> openSettings();
}
