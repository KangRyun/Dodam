import 'package:permission_handler/permission_handler.dart';

import '../../domain/services/push_permission_service.dart';

// 기기 알림 권한 요청과 앱 설정 이동 처리
final class DevicePushPermissionService implements PushPermissionService {
  @override
  Future<PushPermissionStatus> request() async {
    final status = await Permission.notification.request();
    if (status.isGranted) return PushPermissionStatus.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return PushPermissionStatus.permanentlyDenied;
    }
    return PushPermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
