package com.ssafy.b209.storage.audio;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 음성 파일 검증·저장 중 공개 가능한 오류 코드다. */
public enum AudioStorageErrorCode implements ErrorCode {
  EMPTY_AUDIO_FILE(HttpStatus.BAD_REQUEST, "AUDIO_400_001", "음성 파일이 비어 있습니다."),
  UNSUPPORTED_AUDIO_FORMAT(HttpStatus.BAD_REQUEST, "AUDIO_400_002", "지원하지 않는 음성 형식입니다."),
  INVALID_AUDIO_FILE(HttpStatus.BAD_REQUEST, "AUDIO_400_003", "유효한 음성 파일이 아닙니다."),
  AUDIO_DURATION_EXCEEDED(HttpStatus.BAD_REQUEST, "AUDIO_400_004", "음성 길이가 허용 범위를 초과했습니다."),
  INVALID_STORAGE_PATH(HttpStatus.BAD_REQUEST, "AUDIO_400_005", "유효하지 않은 음성 저장 경로입니다."),
  AUDIO_FILE_TOO_LARGE(HttpStatus.PAYLOAD_TOO_LARGE, "AUDIO_413_001", "음성 파일 크기가 허용 범위를 초과했습니다."),
  AUDIO_STORAGE_CONFLICT(HttpStatus.CONFLICT, "AUDIO_409_001", "음성 파일 저장 요청이 충돌했습니다."),
  AUDIO_NOT_FOUND(HttpStatus.NOT_FOUND, "AUDIO_404_001", "음성 파일을 찾을 수 없습니다."),
  AUDIO_STORAGE_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "AUDIO_500_001", "음성 파일 저장 중 오류가 발생했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  AudioStorageErrorCode(HttpStatus httpStatus, String code, String message) {
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
