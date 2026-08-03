import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/photo_picker_adapter.dart';

/// 백엔드 업로드 계약(JPEG/PNG, 최대 10MiB)과 맞춘 클라이언트 사전 검증
/// 상한. 서버가 최종 권한자이며(흐림·그림 영역 등은 서버만 판단할 수 있다),
/// 여기서는 업로드 전에 걸러낼 수 있는 형식·크기·디코딩 가능 여부만 본다.
const int kMaxPhotoUploadBytes = 10 * 1024 * 1024;

/// 그림 전체가 알아볼 수 있게 나오는지 가늠하는 최소·최대 변 길이(px).
const int kMinPhotoEdgePx = 320;
const int kMaxPhotoEdgePx = 8192;

/// 서버 저장소가 실제로 받는 형식과 같은 목록이다. `LocalImageStorage`는
/// PNG·JPEG만 재인코딩할 수 있고 그 외에는 `STORAGE_400_002`로 거절하므로,
/// WEBP를 여기서 통과시키면 업로드까지 간 뒤에야 실패한다. ERD v1.1 §195도
/// 공통 파일 규약을 PNG/JPEG로 고정한다 — 넓히려면 명세·서버·앱을 함께 바꾼다.
const Set<String> kSupportedPhotoMimeTypes = {'image/jpeg', 'image/png'};

enum PhotoValidationErrorType {
  unsupportedFormat,
  signatureMismatch,
  tooLarge,
  edgeTooSmall,
  edgeTooLarge,
  undecodable,
}

/// 확장자·MIME 힌트가 아니라 파일 앞머리 바이트로 실제 형식을 확인한다.
/// 이름만 바꾼 파일이 잘못된 형식으로 통과하는 것을 막는다.
bool _matchesSignature(Uint8List bytes, String mimeType) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  return switch (mimeType) {
    'image/jpeg' => startsWith(const [0xFF, 0xD8, 0xFF]),
    'image/png' => startsWith(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]),
    _ => false,
  };
}

final class ValidatedPhoto {
  const ValidatedPhoto({
    required this.photo,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final PickedPhoto photo;
  final String mimeType;
  final int width;
  final int height;
}

sealed class PhotoValidationResult {
  const PhotoValidationResult();
}

final class PhotoValidationOk extends PhotoValidationResult {
  const PhotoValidationOk(this.validated);
  final ValidatedPhoto validated;
}

final class PhotoValidationFailed extends PhotoValidationResult {
  const PhotoValidationFailed(this.type);
  final PhotoValidationErrorType type;
}

/// 사진 바이트에서 (width, height)를 읽어낸다. 테스트는 실제 이미지 디코딩
/// 대신 가짜 구현을 주입해 임의의 크기·디코딩 실패를 즉시 재현한다.
typedef PhotoDimensionReader =
    Future<(int width, int height)> Function(Uint8List bytes);

Future<(int, int)> readPhotoDimensions(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final width = frame.image.width;
  final height = frame.image.height;
  frame.image.dispose();
  return (width, height);
}

String? _mimeTypeFromFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  return null;
}

/// picker가 준 MIME을 서버와 같은 방식으로 canonical 값으로 바꾼다.
///
/// 서버 `LocalImageStorage.fromContentType`은 `trim().toLowerCase()` 뒤
/// `image/jpg`를 `image/jpeg`로 정규화한 다음 형식을 판정한다. 여기서 같은
/// 정규화를 하지 않으면 `image/jpg`를 돌려주는 기기의 정상 JPEG가 서버는
/// 받아 줄 파일인데도 선택 단계에서 막힌다. 정규화한 값은 이후 signature
/// 판정과 multipart Content-Type에 그대로 쓰여 판정 로직이 갈라지지 않는다.
String? _canonicalMimeType(String? mimeType) {
  if (mimeType == null) return null;
  final normalized = mimeType.trim().toLowerCase();
  // 빈 문자열은 "플랫폼이 알려주지 않음"과 같으므로 확장자 보완으로 넘긴다.
  if (normalized.isEmpty) return null;
  return normalized == 'image/jpg' ? 'image/jpeg' : normalized;
}

Future<PhotoValidationResult> validatePickedPhoto(
  PickedPhoto photo, {
  PhotoDimensionReader dimensionReader = readPhotoDimensions,
  int maxBytes = kMaxPhotoUploadBytes,
  int minEdgePx = kMinPhotoEdgePx,
  int maxEdgePx = kMaxPhotoEdgePx,
}) async {
  final mimeType =
      _canonicalMimeType(photo.mimeType) ??
      _mimeTypeFromFileName(photo.fileName);
  if (mimeType == null || !kSupportedPhotoMimeTypes.contains(mimeType)) {
    return const PhotoValidationFailed(
      PhotoValidationErrorType.unsupportedFormat,
    );
  }
  if (!_matchesSignature(photo.bytes, mimeType)) {
    return const PhotoValidationFailed(
      PhotoValidationErrorType.signatureMismatch,
    );
  }
  if (photo.bytes.lengthInBytes > maxBytes) {
    return const PhotoValidationFailed(PhotoValidationErrorType.tooLarge);
  }
  try {
    final (width, height) = await dimensionReader(photo.bytes);
    if (width <= 0 || height <= 0) {
      return const PhotoValidationFailed(PhotoValidationErrorType.undecodable);
    }
    if (width < minEdgePx || height < minEdgePx) {
      return const PhotoValidationFailed(PhotoValidationErrorType.edgeTooSmall);
    }
    if (width > maxEdgePx || height > maxEdgePx) {
      return const PhotoValidationFailed(PhotoValidationErrorType.edgeTooLarge);
    }
    return PhotoValidationOk(
      ValidatedPhoto(
        photo: photo,
        mimeType: mimeType,
        width: width,
        height: height,
      ),
    );
  } on Object {
    return const PhotoValidationFailed(PhotoValidationErrorType.undecodable);
  }
}
