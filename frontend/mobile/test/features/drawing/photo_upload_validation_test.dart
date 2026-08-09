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

/// 진짜 WEBP 파일 앞머리: `RIFF` + 4바이트 크기 + `WEBP`.
final _webpBytes = _withSignature(const [
  0x52,
  0x49,
  0x46,
  0x46,
  0x00,
  0x00,
  0x00,
  0x00,
  0x57,
  0x45,
  0x42,
  0x50,
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

    // 서버는 `image/jpg`를 `image/jpeg`로 정규화해 받는다. 여기서 막으면
    // 서버가 받아 줄 정상 JPEG를 선택 단계에서 거절하게 된다.
    test('image/jpg는 JPEG로 정규화해 통과시킨다', () async {
      final result = await _validate(
        _photo(_jpegBytes, fileName: 'photo.jpg', mimeType: 'image/jpg'),
      );

      expect(result, isA<PhotoValidationOk>());
      // 정규화한 값이 그대로 multipart Content-Type으로 나간다.
      expect((result as PhotoValidationOk).validated.mimeType, 'image/jpeg');
    });

    test('대소문자·앞뒤 공백이 섞인 MIME도 서버와 같게 정규화한다', () async {
      for (final mimeType in ['IMAGE/JPEG', ' image/jpeg ', 'Image/Jpg']) {
        final result = await _validate(
          _photo(_jpegBytes, fileName: 'photo.jpg', mimeType: mimeType),
        );

        expect(result, isA<PhotoValidationOk>(), reason: mimeType);
        expect(
          (result as PhotoValidationOk).validated.mimeType,
          'image/jpeg',
          reason: mimeType,
        );
      }
    });

    test('빈 MIME 문자열은 확장자 보완으로 넘긴다', () async {
      expect(
        await _validate(
          _photo(_pngBytes, fileName: 'photo.png', mimeType: '   '),
        ),
        isA<PhotoValidationOk>(),
      );
    });

    // 정규화는 형식 주장만 바꾼다 — 실제 bytes 검증은 그대로 통과해야 한다.
    test('image/jpg인데 실제 bytes가 PNG면 signatureMismatch로 막는다', () async {
      expect(
        await _validate(
          _photo(_pngBytes, fileName: 'photo.jpg', mimeType: 'image/jpg'),
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.signatureMismatch,
        ),
      );
    });

    test('image/jpg인데 실제 bytes가 WEBP면 signatureMismatch로 막는다', () async {
      expect(
        await _validate(
          _photo(_webpBytes, fileName: 'photo.jpg', mimeType: 'image/jpg'),
        ),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.signatureMismatch,
        ),
      );
    });

    // 정규화가 WEBP까지 열어 주지 않는지 고정한다.
    test('WEBP는 MIME 대소문자·공백을 바꿔도 계속 막는다', () async {
      for (final mimeType in ['image/webp', 'IMAGE/WEBP', ' image/webp ']) {
        expect(
          await _validate(
            _photo(_webpBytes, fileName: 'drawing.webp', mimeType: mimeType),
          ),
          isA<PhotoValidationFailed>().having(
            (failed) => failed.type,
            'type',
            PhotoValidationErrorType.unsupportedFormat,
          ),
          reason: mimeType,
        );
      }
    });

    // 서버 저장소가 PNG·JPEG만 재인코딩할 수 있어(STORAGE_400_002) WEBP는
    // 업로드 전에 막는다. 여기서 통과시키면 아이가 전송을 마친 뒤에 실패한다.
    test('정상 WEBP는 업로드 전에 unsupportedFormat으로 막는다', () async {
      final result = await _validate(
        _photo(_webpBytes, fileName: 'drawing.webp', mimeType: 'image/webp'),
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

    test('mimeType 없이 .webp 확장자만 있어도 막는다', () async {
      final result = await _validate(
        _photo(_webpBytes, fileName: 'drawing.WEBP'),
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

    // 지원 형식으로 위장해도 실제 bytes가 WEBP면 signature 단계에서 걸린다.
    for (final (label, fileName, mimeType) in <(String, String, String?)>[
      ('JPEG 확장자로 위장', 'drawing.jpg', null),
      ('JPEG MIME으로 위장', 'drawing.jpg', 'image/jpeg'),
      ('PNG MIME으로 위장', 'drawing.png', 'image/png'),
    ]) {
      test('WEBP bytes를 $label해도 signatureMismatch로 막는다', () async {
        final result = await _validate(
          _photo(_webpBytes, fileName: fileName, mimeType: mimeType),
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
    }

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

    // 빈 파일은 signature 길이 검사에서 걸려야 한다 — 인덱스 접근으로 예외를
    // 던지거나 디코더까지 내려가면 안 된다.
    test('0-byte 파일은 예외 없이 막고 디코더까지 내려가지 않는다', () async {
      var decoderCalls = 0;
      final result = await validatePickedPhoto(
        _photo(Uint8List(0), fileName: 'empty.jpg', mimeType: 'image/jpeg'),
        dimensionReader: (_) async {
          decoderCalls += 1;
          return (800, 600);
        },
      );

      expect(
        result,
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.signatureMismatch,
        ),
      );
      expect(decoderCalls, 0);
    });

    test('확장자·mimeType이 없는 0-byte 파일도 예외 없이 막는다', () async {
      expect(
        await _validate(_photo(Uint8List(0), fileName: 'empty')),
        isA<PhotoValidationFailed>().having(
          (failed) => failed.type,
          'type',
          PhotoValidationErrorType.unsupportedFormat,
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
