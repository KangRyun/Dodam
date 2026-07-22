package com.ssafy.b209.analysis.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 그림 분석 요청, 결과 저장과 조회 과정에서 외부에 반환할 안전한 오류 코드를 정의한다. */
public enum DrawingAnalysisErrorCode implements ErrorCode {
  /** 분석 대상 그림 파일을 찾을 수 없는 경우다. */
  DRAWING_ANALYSIS_TARGET_NOT_FOUND(HttpStatus.NOT_FOUND, "ANALYSIS_404_001", "분석할 그림을 찾을 수 없습니다."),
  /** 세션 상태, 그림 소속 또는 스냅샷 유형이 분석을 허용하지 않는 경우다. */
  DRAWING_ANALYSIS_NOT_ALLOWED(HttpStatus.CONFLICT, "ANALYSIS_409_001", "현재 상태에서는 그림을 분석할 수 없습니다."),
  /** 같은 그림과 작업 유형의 진행 또는 성공 분석이 이미 존재하는 경우다. */
  DRAWING_ANALYSIS_ALREADY_EXISTS(
      HttpStatus.CONFLICT, "ANALYSIS_409_002", "해당 그림의 분석이 이미 진행되었거나 완료되었습니다."),
  /** AI Client가 분석 요청을 완료하지 못한 경우다. */
  DRAWING_ANALYSIS_REQUEST_FAILED(
      HttpStatus.BAD_GATEWAY, "ANALYSIS_502_001", "그림 분석 요청을 완료하지 못했습니다."),
  /** AI Client 응답이 합의한 계약과 일치하지 않는 경우다. */
  DRAWING_ANALYSIS_INVALID_RESPONSE(
      HttpStatus.BAD_GATEWAY, "ANALYSIS_502_002", "그림 분석 응답을 처리할 수 없습니다."),
  /** 유효한 분석 결과를 데이터베이스에 저장하지 못한 경우다. */
  DRAWING_ANALYSIS_RESULT_SAVE_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "ANALYSIS_500_001", "그림 분석 결과 저장 중 오류가 발생했습니다."),
  /** 요청한 Session에서 분석을 찾을 수 없는 경우다. */
  DRAWING_ANALYSIS_NOT_FOUND(HttpStatus.NOT_FOUND, "ANALYSIS_404_002", "그림 분석 결과를 찾을 수 없습니다."),
  /** 분석 상태와 저장된 Model·Detection·실패 정보가 서로 모순되는 경우다. */
  DRAWING_ANALYSIS_RESULT_INCONSISTENT(
      HttpStatus.INTERNAL_SERVER_ERROR, "ANALYSIS_500_002", "그림 분석 결과 상태가 올바르지 않습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  DrawingAnalysisErrorCode(HttpStatus httpStatus, String code, String message) {
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
