package com.ssafy.b209.global.exception;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.ErrorCode;
import com.ssafy.b209.global.response.FieldErrorDetail;
import com.ssafy.b209.global.response.ValidationErrorData;
import com.ssafy.b209.user.dto.response.GuardianPinStatusResponse;
import com.ssafy.b209.user.exception.GuardianPinException;
import jakarta.validation.ConstraintViolationException;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.validation.BindException;
import org.springframework.validation.BindingResult;
import org.springframework.validation.ObjectError;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * Controller 계층에서 전달된 예외를 공통 {@link ApiErrorResponse}와 적절한 HTTP Status로 변환한다.
 *
 * <p>예상 가능한 클라이언트 오류와 예상하지 못한 서버 오류의 Logging 수준을 구분한다. 응답에는 예외 원문, Stack Trace, 요청 값과 데이터베이스 내부 정보를
 * 포함하지 않는다.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

  private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

  /** 상태를 보관하지 않는 전역 예외 처리기를 생성한다. */
  public GlobalExceptionHandler() {}

  /**
   * 보호자 PIN 실패에 현재 상태를 함께 실어 응답한다 (S15P11B209-879).
   *
   * <p>{@code PIN_MISMATCH}는 남은 시도 횟수, {@code PIN_LOCKED}는 잠금 해제 시각이 있어야 화면을 만들 수 있다. 그 값을 오류 메시지
   * 문자열에 섞지 않고 성공 응답과 같은 구조체로 {@code data}에 싣는다. PIN 원문·해시는 담기지 않는다.
   */
  @ExceptionHandler(GuardianPinException.class)
  ResponseEntity<ApiErrorResponse<GuardianPinStatusResponse>> handleGuardianPinException(
      GuardianPinException exception) {
    ErrorCode errorCode = exception.getErrorCode();
    logClientError(errorCode);
    return response(errorCode, exception.getStatus());
  }

  @ExceptionHandler(BusinessException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleBusinessException(BusinessException exception) {
    ErrorCode errorCode = exception.getErrorCode();
    if (errorCode.getHttpStatus().is5xxServerError()) {
      logServerError("Handled business server error", errorCode, exception);
    } else {
      logClientError(errorCode);
    }
    return response(errorCode);
  }

  @ExceptionHandler(AuthenticationException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleAuthenticationException(
      AuthenticationException exception) {
    ErrorCode errorCode = AuthErrorCode.AUTHENTICATION_REQUIRED;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(AccessDeniedException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleAccessDeniedException(
      AccessDeniedException exception) {
    ErrorCode errorCode = AuthErrorCode.ACCESS_DENIED;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(MethodArgumentNotValidException.class)
  ResponseEntity<ApiErrorResponse<ValidationErrorData>> handleMethodArgumentNotValidException(
      MethodArgumentNotValidException exception) {
    ErrorCode errorCode = CommonErrorCode.INVALID_INPUT_VALUE;
    logClientError(errorCode);
    return response(errorCode, toValidationErrorData(exception.getBindingResult()));
  }

  @ExceptionHandler(BindException.class)
  ResponseEntity<ApiErrorResponse<ValidationErrorData>> handleBindException(
      BindException exception) {
    ErrorCode errorCode = CommonErrorCode.INVALID_INPUT_VALUE;
    logClientError(errorCode);
    return response(errorCode, toValidationErrorData(exception.getBindingResult()));
  }

  @ExceptionHandler(ConstraintViolationException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleConstraintViolationException(
      ConstraintViolationException exception) {
    ErrorCode errorCode = CommonErrorCode.INVALID_INPUT_VALUE;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(HandlerMethodValidationException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleHandlerMethodValidationException(
      HandlerMethodValidationException exception) {
    if (exception.isForReturnValue()) {
      ErrorCode errorCode = CommonErrorCode.INTERNAL_SERVER_ERROR;
      logServerError("Handled return value validation error", errorCode, exception);
      return response(errorCode);
    }

    ErrorCode errorCode = CommonErrorCode.INVALID_INPUT_VALUE;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(MethodArgumentTypeMismatchException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleMethodArgumentTypeMismatchException(
      MethodArgumentTypeMismatchException exception) {
    ErrorCode errorCode = CommonErrorCode.INVALID_TYPE_VALUE;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(HttpMessageNotReadableException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleHttpMessageNotReadableException(
      HttpMessageNotReadableException exception) {
    ErrorCode errorCode = CommonErrorCode.MESSAGE_NOT_READABLE;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(MissingServletRequestParameterException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleMissingServletRequestParameterException(
      MissingServletRequestParameterException exception) {
    ErrorCode errorCode = CommonErrorCode.MISSING_REQUEST_PARAMETER;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(MissingServletRequestPartException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleMissingServletRequestPartException(
      MissingServletRequestPartException exception) {
    ErrorCode errorCode = CommonErrorCode.MISSING_REQUEST_PARAMETER;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleHttpRequestMethodNotSupportedException(
      HttpRequestMethodNotSupportedException exception) {
    ErrorCode errorCode = CommonErrorCode.METHOD_NOT_ALLOWED;
    logClientError(errorCode);

    HttpHeaders headers = new HttpHeaders();
    Set<HttpMethod> supportedMethods = exception.getSupportedHttpMethods();
    if (supportedMethods != null) {
      headers.setAllow(supportedMethods);
    }

    return new ResponseEntity<>(ApiErrorResponse.of(errorCode), headers, errorCode.getHttpStatus());
  }

  @ExceptionHandler(NoResourceFoundException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleNoResourceFoundException(
      NoResourceFoundException exception) {
    ErrorCode errorCode = CommonErrorCode.RESOURCE_NOT_FOUND;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(DataIntegrityViolationException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleDataIntegrityViolationException(
      DataIntegrityViolationException exception) {
    ErrorCode errorCode = CommonErrorCode.DATA_INTEGRITY_VIOLATION;
    log.warn("Handled data integrity violation: code={}", errorCode.getCode());
    return response(errorCode);
  }

  @ExceptionHandler(MaxUploadSizeExceededException.class)
  ResponseEntity<ApiErrorResponse<Void>> handleMaxUploadSizeExceededException(
      MaxUploadSizeExceededException exception) {
    ErrorCode errorCode = CommonErrorCode.PAYLOAD_TOO_LARGE;
    logClientError(errorCode);
    return response(errorCode);
  }

  @ExceptionHandler(Exception.class)
  ResponseEntity<ApiErrorResponse<Void>> handleException(Exception exception) {
    ErrorCode errorCode = CommonErrorCode.INTERNAL_SERVER_ERROR;
    logServerError("Handled server error", errorCode, exception);
    return response(errorCode);
  }

  private ValidationErrorData toValidationErrorData(BindingResult bindingResult) {
    List<FieldErrorDetail> fieldErrors =
        bindingResult.getFieldErrors().stream()
            .map(error -> new FieldErrorDetail(error.getField(), safeMessage(error)))
            .distinct()
            .sorted(
                Comparator.comparing(FieldErrorDetail::field)
                    .thenComparing(FieldErrorDetail::message))
            .toList();
    List<String> globalErrors =
        bindingResult.getGlobalErrors().stream()
            .map(this::safeMessage)
            .distinct()
            .sorted()
            .toList();
    return new ValidationErrorData(fieldErrors, globalErrors);
  }

  private String safeMessage(ObjectError error) {
    return Objects.requireNonNullElse(
        error.getDefaultMessage(), CommonErrorCode.INVALID_INPUT_VALUE.getMessage());
  }

  private void logClientError(ErrorCode errorCode) {
    log.debug("Handled client error: code={}", errorCode.getCode());
  }

  private void logServerError(String description, ErrorCode errorCode, Exception exception) {
    log.error(
        "{}: code={}, exceptionType={}, stackTrace={}",
        description,
        errorCode.getCode(),
        exception.getClass().getName(),
        Arrays.toString(exception.getStackTrace()));
  }

  private ResponseEntity<ApiErrorResponse<Void>> response(ErrorCode errorCode) {
    return ResponseEntity.status(errorCode.getHttpStatus()).body(ApiErrorResponse.of(errorCode));
  }

  private <T> ResponseEntity<ApiErrorResponse<T>> response(ErrorCode errorCode, T data) {
    return ResponseEntity.status(errorCode.getHttpStatus())
        .body(ApiErrorResponse.of(errorCode, data));
  }
}
