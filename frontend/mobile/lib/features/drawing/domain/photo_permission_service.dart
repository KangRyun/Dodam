/// 사진 입력에 필요한 기기 권한 종류다.
enum PhotoPermissionKind { camera, photos }

/// 시스템 picker가 권한 오류를 반환한 뒤 확인한 현재 권한 상태다.
enum PhotoPermissionStatus { denied, permanentlyDenied, restricted }

/// 사진 입력 권한의 현재 상태 확인과 앱 설정 이동을 추상화한다.
///
/// 시스템 Camera·Photo Picker가 실제 권한 요청을 담당하며, 이 경계는 거부
/// 이후 사용자가 복구할 수 있는 안내를 제공하는 데만 사용한다.
abstract interface class PhotoPermissionService {
  /// [kind] 권한이 다시 요청 가능한지 또는 설정에서만 변경 가능한지 확인한다.
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind);

  /// 사용자가 권한을 직접 변경할 수 있도록 현재 앱의 기기 설정을 연다.
  ///
  /// 설정 화면을 열었으면 `true`, 열지 못했으면 `false`를 반환한다.
  Future<bool> openSettings();
}
