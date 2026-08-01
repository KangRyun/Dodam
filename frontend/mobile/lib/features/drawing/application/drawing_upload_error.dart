import 'package:flutter/material.dart';

import '../../../core/network/network.dart';
import 'photo_upload_validation.dart';

enum DrawingUploadEndpoint { upload, completion }

bool isDrawingUploadCancelled(Object? failure) =>
    failure is ApiTransportFailure &&
    failure.type == ApiTransportFailureType.cancelled;

/// 사진 업로드 실패를 아이콘+문구+재시도 가능 여부로 바꾼다.
///
/// 색상만으로 오류를 구분하지 않는다 — 아이콘과 문구를 항상 함께 보여준다.
/// 서버 오류 코드는 Backend의 실제 wire 계약(`STORAGE_422_001`,
/// `DRAWING_UPLOAD_FAILED`)만 분기하고, 나머지는 공통 API 오류 표현을 쓴다.
final class DrawingUploadErrorPresentation {
  const DrawingUploadErrorPresentation({
    required this.icon,
    required this.message,
    required this.canRetry,
  });

  final IconData icon;
  final String message;
  final bool canRetry;

  factory DrawingUploadErrorPresentation.of(
    Object? failure, {
    DrawingUploadEndpoint endpoint = DrawingUploadEndpoint.upload,
  }) {
    final presentation = ApiFailurePresentation.of(
      failure,
      childFriendly: true,
    );
    final canRetry =
        presentation.canRetry ||
        (endpoint == DrawingUploadEndpoint.completion &&
            failure is ApiResponseFailure &&
            failure.statusCode == 409 &&
            failure.error?.code == 'DRAWING_409_017');
    if (failure is ApiResponseFailure) {
      switch (failure.error?.code) {
        case 'STORAGE_422_001':
          return DrawingUploadErrorPresentation(
            icon: Icons.aspect_ratio_rounded,
            message: '사진 크기가 적절하지 않아요. 다른 사진을 선택해 주세요.',
            canRetry: canRetry,
          );
        case 'DRAWING_UPLOAD_FAILED':
          return DrawingUploadErrorPresentation(
            icon: Icons.cloud_off_rounded,
            message: '사진을 올리지 못했어요. 다시 시도해 주세요.',
            canRetry: canRetry,
          );
      }
    }
    return DrawingUploadErrorPresentation(
      icon: presentation.isConnectivity
          ? Icons.wifi_off_rounded
          : Icons.error_outline_rounded,
      message: presentation.message,
      canRetry: canRetry,
    );
  }
}

/// 형식·크기·디코딩 실패를 같은 아이콘+문구 규약으로 보여준다(업로드 전
/// 클라이언트 검증이라 서버 응답 없이도 즉시 표시한다).
DrawingUploadErrorPresentation presentationForValidationError(
  PhotoValidationErrorType type,
) => switch (type) {
  PhotoValidationErrorType.unsupportedFormat =>
    const DrawingUploadErrorPresentation(
      icon: Icons.image_not_supported_rounded,
      message: 'JPEG·PNG·WEBP 형식의 사진만 사용할 수 있어요. 다른 사진을 선택해 주세요.',
      canRetry: false,
    ),
  PhotoValidationErrorType.signatureMismatch =>
    const DrawingUploadErrorPresentation(
      icon: Icons.rule_rounded,
      message: '사진 형식을 확인할 수 없어요. 다른 사진을 선택해 주세요.',
      canRetry: false,
    ),
  PhotoValidationErrorType.tooLarge => const DrawingUploadErrorPresentation(
    icon: Icons.sd_card_rounded,
    message: '사진 용량이 너무 커요(최대 10MB). 다른 사진을 선택해 주세요.',
    canRetry: false,
  ),
  PhotoValidationErrorType.edgeTooSmall => const DrawingUploadErrorPresentation(
    icon: Icons.zoom_in_rounded,
    message: '사진이 너무 작아요. 그림이 크게 보이도록 다시 찍어 주세요.',
    canRetry: false,
  ),
  PhotoValidationErrorType.edgeTooLarge => const DrawingUploadErrorPresentation(
    icon: Icons.zoom_out_rounded,
    message: '사진이 너무 커요. 다른 사진을 선택해 주세요.',
    canRetry: false,
  ),
  PhotoValidationErrorType.undecodable => const DrawingUploadErrorPresentation(
    icon: Icons.broken_image_rounded,
    message: '사진을 열어볼 수 없어요. 다른 사진을 선택해 주세요.',
    canRetry: false,
  ),
};
