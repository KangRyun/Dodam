import 'package:image_picker/image_picker.dart';

import '../domain/photo_picker_adapter.dart';

/// [PhotoPickerAdapter]의 실제 구현. `image_picker`가 카메라는 시스템 카메라
/// 앱 인텐트로, 앨범은 Android Photo Picker(13+)·iOS PHPicker로 위임한다.
///
/// `requestFullMetadata: false`로 호출해 iOS에서 전체 사진 라이브러리
/// 메타데이터 접근을 요청하지 않는다 — 사용자가 고른 사진 한 장만 받는다.
final class ImagePickerPhotoAdapter implements PhotoPickerAdapter {
  ImagePickerPhotoAdapter([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedPhoto?> pickFromCamera() => _pick(ImageSource.camera);

  @override
  Future<PickedPhoto?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<PickedPhoto?> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedPhoto(
      bytes: bytes,
      fileName: file.name,
      mimeType: file.mimeType,
    );
  }
}
