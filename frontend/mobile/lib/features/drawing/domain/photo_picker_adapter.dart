import 'dart:typed_data';

/// 시스템 카메라·앨범(Photo Picker)에서 고른 사진 한 장.
final class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;

  /// 플랫폼이 알려주지 않으면 null일 수 있다 — 검증 단계에서 확장자로 보완한다.
  final String? mimeType;
}

/// 사진으로 그림 활동을 시작할 때 쓰는 사진 획득 경계.
///
/// 시스템 카메라 앱 위임과 시스템 Photo Picker만 사용한다(CLAUDE.md 정책).
/// 커스텀 인앱 카메라 프리뷰나 앨범 그리드는 만들지 않는다. `pickImage`
/// MethodChannel을 화면이 직접 호출하지 않도록 이 인터페이스로 경계를
/// 분리해, 테스트는 실제 채널 대신 Fake 구현을 주입한다.
abstract interface class PhotoPickerAdapter {
  /// 시스템 카메라 앱으로 위임해 촬영한다. 사용자가 취소하면 `null`.
  Future<PickedPhoto?> pickFromCamera();

  /// 시스템 Photo Picker에서 사진 한 장을 고른다. 사용자가 취소하면 `null`.
  Future<PickedPhoto?> pickFromGallery();
}
