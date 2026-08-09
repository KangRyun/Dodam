enum MicrophonePermissionStatus { granted, denied, permanentlyDenied }

abstract interface class MicrophonePermissionService {
  Future<MicrophonePermissionStatus> request();

  Future<bool> openSettings();
}
