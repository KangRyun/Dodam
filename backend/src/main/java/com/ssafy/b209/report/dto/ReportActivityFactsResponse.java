package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 그림 활동의 객관적 사실 기록을 반환한다.
 *
 * <p>모든 수치는 해석을 배제한 객관적 기록이며, 감정 추정이나 위험도 등 판단성 값은 포함하지 않는다.
 *
 * @param detectedObjects 최신 리포트는 VLM 관찰 서술 기반으로 저장한 그린 것 이름 목록이며, 과거 리포트만 0.50 이상 YOLO 탐지 객체명 폴백
 * @param drawingDurationMs 그림 활동 시간(ms)이며 미집계면 {@code null}
 * @param pauseCount 일시 정지 횟수이며 미집계면 {@code null}
 * @param eraseCount 지우기 횟수이며 미집계면 {@code null}
 * @param pressureAvailable 필압 데이터 존재 여부
 * @param notes 객관적 활동 주의사항 목록
 */
@Schema(description = "활동 사실 기록")
public record ReportActivityFactsResponse(
    List<String> detectedObjects,
    Long drawingDurationMs,
    Integer pauseCount,
    Integer eraseCount,
    boolean pressureAvailable,
    List<String> notes,
    Integer totalDurationSec,
    Integer drawingDurationSec,
    Integer undoCount,
    Integer questionCount,
    Integer answerCount,
    Integer skipCount,
    Integer detectedElementCount,
    Double pressureValue,
    boolean truncated,
    boolean aggregatedHtp) {

  /**
   * 875 확장 이전 형태로 만든다.
   *
   * <p>신규 필드가 없던 호출부(주로 테스트)를 그대로 두기 위한 생성자다. 초 단위 값은 밀리초에서 유도하고 나머지는 집계하지 못한 상태({@code null})로 둔다
   * — 0으로 채우면 화면이 "0회"를 사실로 표시한다.
   *
   * @param detectedObjects 그린 것 목록
   * @param drawingDurationMs 그린 시간(밀리초)이며 집계하지 못했으면 {@code null}
   * @param pauseCount 멈춤 횟수
   * @param eraseCount 지우기 횟수
   * @param pressureAvailable 필압 수치 유무
   * @param notes 참고 문구 목록
   */
  public ReportActivityFactsResponse(
      List<String> detectedObjects,
      Long drawingDurationMs,
      Integer pauseCount,
      Integer eraseCount,
      boolean pressureAvailable,
      List<String> notes) {
    this(
        detectedObjects,
        drawingDurationMs,
        pauseCount,
        eraseCount,
        pressureAvailable,
        notes,
        toSeconds(drawingDurationMs),
        toSeconds(drawingDurationMs),
        null,
        null,
        null,
        null,
        null,
        null,
        false,
        false);
  }

  /**
   * 밀리초 값을 초로 바꾼다 (875 §8-1 · 계약 §5-d8).
   *
   * <p>{@code null}(집계 못 함)과 {@code 0}(0초)을 구분한다 — {@code null}을 0으로 만들면 화면에 "0초 그렸다"가 뜬다. 기존 밀리초
   * 필드는 그대로 유지한다(FE 가 두 형태를 모두 읽는다).
   *
   * @param milliseconds 밀리초 값이며 집계하지 못했으면 {@code null}
   * @return 내림한 초 값이며 입력이 {@code null}이면 {@code null}
   */
  public static Integer toSeconds(Long milliseconds) {
    return milliseconds == null ? null : (int) (milliseconds / 1000L);
  }
}
