package com.ssafy.b209.drawing.repository;

import java.time.LocalDateTime;

/**
 * 월간 감정 달력 집계에 사용할 그림 활동과 아동 선택 감정 한 쌍의 읽기 전용 Projection이다.
 *
 * <p>세션 하나에 선택 감정이 여러 건이면 같은 세션 식별자로 여러 행이 반환되므로, 활동 수를 세는 계층은 세션 식별자로 중복을 제거해야 한다. 선택 감정이 없는 세션도
 * 감정 값이 {@code null}인 한 행으로 반환된다.
 *
 * <p>아동이 직접 선택한 감정만 담으며 AI 추정 감정과 위험도, 전문가 전용 정보는 포함하지 않는다.
 */
public interface EmotionCalendarRowProjection {

  /**
   * 감정이 속한 그림 활동 세션 식별자를 반환한다.
   *
   * @return 그림 활동 세션 식별자
   */
  Long getDrawingSessionId();

  /**
   * 그림 활동 시작 시각을 UTC 기준 벽시계 값으로 반환한다.
   *
   * @return UTC 기준 활동 시작 시각
   */
  LocalDateTime getStartedAt();

  /**
   * 아동이 선택한 감정 코드의 DB 문자열을 반환한다.
   *
   * @return 선택 감정 코드 이름, 선택 감정이 없는 세션이면 {@code null}
   */
  String getEmotionCode();

  /**
   * 세션에 연결된 생성 완료 리포트 수를 반환한다.
   *
   * @return 상태가 완료인 리포트 수, 없으면 {@code 0}
   */
  long getCompletedReportCount();
}
