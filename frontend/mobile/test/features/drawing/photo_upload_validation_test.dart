import 'dart:typed_data';

import 'package:dodam/features/drawing/application/photo_upload_validation.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 형식별 실제 파일 앞머리(magic bytes). 검증이 확장자·MIME 힌트가 아니라
/// 바이트를 보는지 확인하기 위해 최소 시그니처만 만들어 쓴다.
Uint8List _withSignature(List<int> signature, {int padTo = 64}) {
  final bytes = Uint8List(padTo);
  for (var i = 0; i < signature.length; i++) {
    bytes[i] = signature[i];
  }
  return bytes;
}

final _jpegBytes = _withSignature(const [0xFF, 0xD8, 0xFF]);
final _pngBytes = _withSignature(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

PickedPhoto _photo(
  Uint8List bytes, {
  String fileName = 'photo.png',
  String? mimeType,
}) => PickedPhoto(bytes: bytes, fileName: fileName, mimeType: mimeType);

Future<PhotoValidationResult> _validate(
  PickedPhoto photo, {
  int width = 800,
  int height = 600,
}) => validatePickedPhoto(photo, dimensionReader: (_) async => (width, height));

void main() {
  group('형식·Signature 검증', () {
    test('JPEG·PNG는 시그니처가 맞으면 통과한다', () async {
      expect(
        await _validate(
          _photo(_jpegBytes, fileName: 'a.jpg', mimeType: 'image/jpeg'),
        ),
        isA<PhotoValidationOk>(),
      );
      expect(
        await _validate(
          _photo(_pngBytes, fileName: 'a.png', mimeType: 'image/png'),
        ),
        isA<PhotoValidationOk>(),
      );
    });

    test('지원하지 않는 형식은 unsupportedFormat으로 막는다', () async {
      final result = await _validate(
        _photo(_pngBytes, fileName: 'a.gif', mimeType: 'image/gif'),
      );

      expect(
        result,
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.unsupportedFormat,
        ),
      );
    });

    test('확장자만 바꾼 파일은 signatureMismatch로 막는다', () async {
      // 내용은 PNG인데 JPEG라고 주장하는 경우.
      final result = await _validate(
        _photo(_pngBytes, fileName: 'fake.jpg', mimeType: 'image/jpeg'),
      );

      expect(
        result,
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.signatureMismatch,
        ),
      );
    });

    test('시그니처가 아예 없는 바이트도 signatureMismatch로 막는다', () async {
      final result = await _validate(
        _photo(
          Uint8List.fromList(const [1, 2, 3, 4]),
          fileName: 'a.png',
          mimeType: 'image/png',
        ),
      );

      expect(
        result,
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.signatureMismatch,
        ),
      );
    });

    test('mimeType이 없으면 확장자로 형식을 보완한 뒤 시그니처를 확인한다', () async {
      expect(
        await _validate(_photo(_pngBytes, fileName: 'a.PNG')),
        isA<PhotoValidationOk>(),
      );
      expect(
        await _validate(_photo(_pngBytes, fileName: 'a.jpeg')),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.signatureMismatch,
        ),
      );
    });
  });

  group('해상도 범위 검증', () {
    test('최소 변 길이(320px) 경계를 지킨다', () async {
      expect(
        await _validate(_photo(_pngBytes), width: kMinPhotoEdgePx, height: 400),
        isA<PhotoValidationOk>(),
      );
      expect(
        await _validate(
          _photo(_pngBytes),
          width: kMinPhotoEdgePx - 1,
          height: 400,
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.edgeTooSmall,
        ),
      );
      // 높이만 작아도 막는다.
      expect(
        await _validate(
          _photo(_pngBytes),
          width: 400,
          height: kMinPhotoEdgePx - 1,
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.edgeTooSmall,
        ),
      );
    });

    test('최대 변 길이(8192px) 경계를 지킨다', () async {
      expect(
        await _validate(
          _photo(_pngBytes),
          width: kMaxPhotoEdgePx,
          height: kMaxPhotoEdgePx,
        ),
        isA<PhotoValidationOk>(),
      );
      expect(
        await _validate(
          _photo(_pngBytes),
          width: kMaxPhotoEdgePx + 1,
          height: 400,
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.edgeTooLarge,
        ),
      );
      // 높이만 커도 막는다.
      expect(
        await _validate(
          _photo(_pngBytes),
          width: 400,
          height: kMaxPhotoEdgePx + 1,
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.edgeTooLarge,
        ),
      );
    });

    test('디코딩 불가·0 크기는 undecodable로 막는다', () async {
      expect(
        await _validate(_photo(_pngBytes), width: 0, height: 0),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.undecodable,
        ),
      );
      expect(
        await validatePickedPhoto(
          _photo(_pngBytes),
          dimensionReader: (_) async => throw const FormatException('bad'),
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.undecodable,
        ),
      );
    });
  });

  group('용량 검증', () {
    test('10MiB를 넘으면 tooLarge로 막는다', () async {
      // 시그니처는 맞지만 용량이 초과된 경우.
      final huge = _withSignature(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ], padTo: kMaxPhotoUploadBytes + 1);

      expect(
        await _validate(_photo(huge)),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.tooLarge,
        ),
      );
    });
  });
}
