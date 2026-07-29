import 'package:flutter/material.dart';

import '../../../core/network/network.dart';
import 'photo_upload_validation.dart';

/// 사진 업로드 실패를 아이콘+문구+재시도 가능 여부로 바꾼다.
///
/// 색상만으로 오류를 구분하지 않는다 — 아이콘과 문구를 항상 함께 보여준다.
/// 서버가 내려주는 4가지 검증 오류 코드(IMAGE_TOO_BLURRY·
/// DRAWING_REGION_NOT_FOUND·IMAGE_DIMENSION_INVALID·UPLOAD_FAILED)는 문자열
/// 코드로만 내려오고 별도 enum으로 계약되어 있지 않아, 기존
/// `failure.error?.code == 'XXX'` 관례를 그대로 따른다.
final class DrawingUploadErrorPresentation {
  const DrawingUploadErrorPresentation({
    required this.icon,
    required this.message,
    required this.canRetry,
  });

  final IconData icon;
  final String message;
  final bool canRetry;

  factory DrawingUploadErrorPresentation.of(Object? failure) {
    if (failure is ApiResponseFailure) {
      switch (failure.error?.code) {
        case 'IMAGE_TOO_BLURRY':
          return const DrawingUploadErrorPresentation(
            icon: Icons.blur_on_rounded,
            message: '사진이 흐려서 잘 안 보여요. 더 밝은 곳에서 다시 찍거나 다른 사진을 골라 주세요.',
            canRetry: true,
          );
        case 'DRAWING_REGION_NOT_FOUND':
          return const DrawingUploadErrorPresentation(
            icon: Icons.crop_free_rounded,
            message: '그림이 잘 보이지 않아요. 그림 전체가 화면에 잘 나오게 다시 찍어 주세요.',
            canRetry: true,
          );
        case 'IMAGE_DIMENSION_INVALID':
          return const DrawingUploadErrorPresentation(
            icon: Icons.aspect_ratio_rounded,
            message: '사진 크기가 적절하지 않아요. 다른 사진을 선택해 주세요.',
            canRetry: true,
          );
        case 'UPLOAD_FAILED':
          return const DrawingUploadErrorPresentation(
            icon: Icons.cloud_off_rounded,
            message: '사진을 올리지 못했어요. 다시 시도해 주세요.',
            canRetry: true,
          );
      }
    }
    final presentation = ApiFailurePresentation.of(
      failure,
      childFriendly: true,
    );
    return DrawingUploadErrorPresentation(
      icon: presentation.isConnectivity
          ? Icons.wifi_off_rounded
          : Icons.error_outline_rounded,
      message: presentation.message,
      canRetry: presentation.canRetry,
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
  PhotoValidationErrorType.tooLarge => const DrawingUploadErrorPresentation(
    icon: Icons.sd_card_rounded,
    message: '사진 용량이 너무 커요(최대 10MB). 다른 사진을 선택해 주세요.',
    canRetry: false,
  ),
  PhotoValidationErrorType.undecodable => const DrawingUploadErrorPresentation(
    icon: Icons.broken_image_rounded,
    message: '사진을 열어볼 수 없어요. 다른 사진을 선택해 주세요.',
    canRetry: false,
  ),
};
