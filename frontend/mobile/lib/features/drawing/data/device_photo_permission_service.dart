import 'package:permission_handler/permission_handler.dart';

import '../domain/photo_permission_service.dart';

/// `permission_handler`를 사용해 사진 입력 권한 상태와 앱 설정 이동을 처리한다.
final class DevicePhotoPermissionService implements PhotoPermissionService {
  const DevicePhotoPermissionService();

  @override
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind) async {
    final status = await _permission(kind).status;
    return _mapStatus(status);
  }

  @override
  Future<PhotoPermissionStatus> request(PhotoPermissionKind kind) async {
    final status = await _permission(kind).request();
    return _mapStatus(status);
  }

  Permission _permission(PhotoPermissionKind kind) => switch (kind) {
    PhotoPermissionKind.camera => Permission.camera,
    PhotoPermissionKind.photos => Permission.photos,
  };

  PhotoPermissionStatus _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return PhotoPermissionStatus.granted;
    }
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
