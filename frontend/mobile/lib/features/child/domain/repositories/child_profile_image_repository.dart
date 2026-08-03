import 'dart:typed_data';

import '../../data/dto/child_dtos.dart';

final class ChildProfileImageUpload {
  const ChildProfileImageUpload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

abstract interface class ChildProfileImageRepository {
  Future<ChildProfileImageUploadResponseDto> uploadProfileImage(
    ChildProfileImageUpload image, {
    void Function(int sent, int total)? onSendProgress,
  });

  Future<Uint8List> downloadProfileImage(String relativeUrl);
}
