import 'package:permission_handler/permission_handler.dart';

import '../domain/photo_permission_service.dart';

/// `permission_handler`를 사용해 사진 입력 권한 상태와 앱 설정 이동을 처리한다.
final class DevicePhotoPermissionService implements PhotoPermissionService {
  @override
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind) async {
    final permission = switch (kind) {
      PhotoPermissionKind.camera => Permission.camera,
      PhotoPermissionKind.photos => Permission.photos,
    };
    final status = await permission.status;
    if (status.isRestricted) {
      return PhotoPermissionStatus.restricted;
    }
    if (status.isPermanentlyDenied) {
      return PhotoPermissionStatus.permanentlyDenied;
    }
    return PhotoPermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
