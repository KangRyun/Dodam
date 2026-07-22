package com.ssafy.b209.storage.image;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 로컬 이미지 검증과 저장 과정에서 외부에 안전하게 전달할 오류 코드를 정의한다. */
public enum ImageStorageErrorCode implements ErrorCode {
  /** 이미지 Byte가 없거나 선언된 크기가 양수가 아닌 경우다. */
  EMPTY_IMAGE_FILE(HttpStatus.BAD_REQUEST, "STORAGE_400_001", "저장할 이미지 파일이 비어 있습니다."),
  /** API 계약에서 허용하지 않은 이미지 형식인 경우다. */
  UNSUPPORTED_IMAGE_FORMAT(HttpStatus.BAD_REQUEST, "STORAGE_400_002", "지원하지 않는 이미지 형식입니다."),
  /** MIME Type, 확장자, Signature 또는 선언 크기가 실제 이미지와 일치하지 않는 경우다. */
  INVALID_IMAGE_FILE(HttpStatus.BAD_REQUEST, "STORAGE_400_003", "유효한 이미지 파일이 아닙니다."),
  /** 정규화된 저장 경로가 허용된 Storage Root를 벗어나거나 안전하지 않은 경우다. */
  INVALID_STORAGE_PATH(HttpStatus.BAD_REQUEST, "STORAGE_400_004", "유효하지 않은 이미지 저장 경로입니다."),
  /** 생성한 최종 파일명이 기존 파일과 충돌하여 안전하게 저장하지 못한 경우다. */
  IMAGE_STORAGE_CONFLICT(HttpStatus.CONFLICT, "STORAGE_409_001", "이미지 저장 요청이 충돌했습니다."),
  /** 선언 크기 또는 실제 Stream 크기가 설정된 최대 크기를 초과한 경우다. */
  IMAGE_FILE_TOO_LARGE(
      HttpStatus.PAYLOAD_TOO_LARGE, "STORAGE_413_001", "이미지 파일 크기가 허용 범위를 초과했습니다."),
  /** 파일 시스템 오류로 이미지를 안전하게 저장하지 못한 경우다. */
  IMAGE_STORAGE_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "STORAGE_500_001", "이미지 저장 중 오류가 발생했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ImageStorageErrorCode(HttpStatus httpStatus, String code, String message) {
    this.httpStatus = httpStatus;
    this.code = code;
    this.message = message;
  }

  @Override
  public HttpStatus getHttpStatus() {
    return httpStatus;
  }

  @Override
  public String getCode() {
    return code;
  }

  @Override
  public String getMessage() {
    return message;
  }
}
