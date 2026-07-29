import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/photo_picker_adapter.dart';

/// 백엔드 업로드 계약(JPEG/PNG/WEBP, 최대 10MiB)과 맞춘 클라이언트 사전 검증
/// 상한. 서버가 최종 권한자이며(흐림·그림 영역 등은 서버만 판단할 수 있다),
/// 여기서는 업로드 전에 걸러낼 수 있는 형식·크기·디코딩 가능 여부만 본다.
const int kMaxPhotoUploadBytes = 10 * 1024 * 1024;

const Set<String> kSupportedPhotoMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

enum PhotoValidationErrorType { unsupportedFormat, tooLarge, undecodable }

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
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}

Future<PhotoValidationResult> validatePickedPhoto(
  PickedPhoto photo, {
  PhotoDimensionReader dimensionReader = readPhotoDimensions,
}) async {
  final mimeType = photo.mimeType ?? _mimeTypeFromFileName(photo.fileName);
  if (mimeType == null || !kSupportedPhotoMimeTypes.contains(mimeType)) {
    return const PhotoValidationFailed(
      PhotoValidationErrorType.unsupportedFormat,
    );
  }
  if (photo.bytes.lengthInBytes > kMaxPhotoUploadBytes) {
    return const PhotoValidationFailed(PhotoValidationErrorType.tooLarge);
  }
  try {
    final (width, height) = await dimensionReader(photo.bytes);
    if (width <= 0 || height <= 0) {
      return const PhotoValidationFailed(PhotoValidationErrorType.undecodable);
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
