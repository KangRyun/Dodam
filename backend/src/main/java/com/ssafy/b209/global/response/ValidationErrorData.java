package com.ssafy.b209.global.response;

import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import java.util.List;
import java.util.Objects;

/**
 * 필드 Validation 오류와 객체 전체 Validation 오류를 구분해 제공하는 불변 상세 데이터다.
 *
 * <p>전달된 목록을 방어적으로 복사하며 사용자 입력 원문은 포함하지 않는다.
 *
 * @param fieldErrors 필드별 오류 목록
 * @param globalErrors 객체 전체에 적용되는 오류 메시지 목록
 */
@JsonPropertyOrder({"fieldErrors", "globalErrors"})
public record ValidationErrorData(List<FieldErrorDetail> fieldErrors, List<String> globalErrors) {

  /** 전달받은 오류 목록의 null 여부를 검증하고 변경할 수 없는 복사본으로 저장한다. */
  public ValidationErrorData {
    fieldErrors = List.copyOf(Objects.requireNonNull(fieldErrors, "fieldErrors must not be null"));
    globalErrors =
        List.copyOf(Objects.requireNonNull(globalErrors, "globalErrors must not be null"));
  }
}
