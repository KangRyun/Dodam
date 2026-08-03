package com.ssafy.b209.global.support;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 길이를 통제할 수 없는 외부 문자열을 VARCHAR 컬럼이 담을 수 있는 크기로 맞춘다.
 *
 * <p>AI 응답처럼 길이가 계약으로 고정되지 않은 값이 길이 제한 컬럼에 그대로 들어가면 MySQL이 data truncation 오류를 내고 Transaction 전체가
 * Rollback된다. 메타데이터 한 항목 때문에 본문 저장까지 무너지지 않도록 저장 직전에 값을 맞춰 넘긴다.
 *
 * <p>MySQL {@code VARCHAR(n)}의 {@code n}은 Byte가 아니라 문자 수이며, utf8mb4에서는 한글도 Emoji 같은 보충 문자도 각각 1자로
 * 센다. 반면 Java {@link String#length()}는 UTF-16 Code Unit 수라 보충 문자를 2로 센다. 그래서 이 클래스는 Code Point 수로
 * 길이를 판단하고 Code Point 경계에서만 자른다. 경계를 무시하고 자르면 Surrogate Pair가 쪼개져 저장할 수 없는 문자열이 만들어진다.
 */
public final class ColumnTextLimiter {

  private static final Logger log = LoggerFactory.getLogger(ColumnTextLimiter.class);

  private ColumnTextLimiter() {}

  /**
   * 값이 컬럼 길이를 넘으면 Code Point 경계에서 잘라 반환한다.
   *
   * <p>자른 경우에만 컬럼 이름과 길이를 경고로 남긴다. 값 자체는 개인정보나 AI 원문을 담을 수 있어 기록하지 않는다.
   *
   * @param value 저장할 값이며 {@code null}이면 그대로 반환한다
   * @param maxCharacters 컬럼이 담을 수 있는 최대 문자 수
   * @param columnName 잘렸을 때 로그로 남길 {@code 테이블.컬럼} 이름
   * @return 최대 문자 수 이내로 맞춘 값
   * @throws IllegalArgumentException {@code maxCharacters}가 양수가 아닌 경우
   */
  public static String fit(String value, int maxCharacters, String columnName) {
    if (maxCharacters <= 0) {
      throw new IllegalArgumentException("maxCharacters must be positive");
    }
    if (value == null) {
      return null;
    }
    int characterCount = value.codePointCount(0, value.length());
    if (characterCount <= maxCharacters) {
      return value;
    }
    log.warn(
        "저장 값이 컬럼 길이를 넘어 잘라 저장합니다. column={}, limit={}, actualCharacters={}",
        columnName,
        maxCharacters,
        characterCount);
    return value.substring(0, value.offsetByCodePoints(0, maxCharacters));
  }
}
