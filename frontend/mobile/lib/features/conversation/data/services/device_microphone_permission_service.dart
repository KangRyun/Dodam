import 'package:permission_handler/permission_handler.dart';

import '../../domain/services/microphone_permission_service.dart';

// 기기 마이크 권한 요청과 앱 설정 이동 처리
final class DeviceMicrophonePermissionService
    implements MicrophonePermissionService {
  @override
  Future<MicrophonePermissionStatus> request() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return MicrophonePermissionStatus.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicrophonePermissionStatus.permanentlyDenied;
    }
    return MicrophonePermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
