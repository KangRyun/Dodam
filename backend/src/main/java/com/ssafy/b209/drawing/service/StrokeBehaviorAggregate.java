package com.ssafy.b209.drawing.service;

import java.util.List;

/**
 * 여러 세션의 행동 집계를 <b>합계와 주제별 내역으로 함께</b> 담는다 (S15P11B209-975).
 *
 * <p><b>왜 둘을 한 값으로 묶는가.</b> 주제별 시간은 "어느 그림에 더 오래 머물렀는가"라는 <b>비교</b>의 재료이고, 비교는 대상이 전부 있을 때만 참이다.
 * 합계는 낼 수 있는데 주제별 내역만 따로 만들 수 있는 구조라면, 언젠가 한쪽만 채워져 세 장 중 두 장으로 순위가 매겨진다. 둘을 같은 값에 담아 <b>전부 아니면 전무를
 * 타입으로 보장한다</b> — 규약이 아니라 구조로 막는 자리다.
 *
 * <p>그래서 이 값 자체가 존재한다는 것은 대상 세션을 <b>하나도 빠짐없이</b> 집계했다는 뜻이다({@link
 * StrokeBehaviorSummaryService#summarizeAllOrNoneBySubject}).
 *
 * @param total 모든 대상 세션을 합산한 요약이다. HTP는 세 활동의 합이다
 * @param subjectDurations 주제별 시간 내역이며 주제 구분이 없는 활동(그림일기·단독 세션)은 <b>빈 목록</b>이다. 순서는 입력 세션 순서를 따른다
 */
public record StrokeBehaviorAggregate(
    StrokeBehaviorSummary total, List<SubjectDuration> subjectDurations) {

  /** 목록이 {@code null}로 만들어져도 빈 목록으로 정규화한다. */
  public StrokeBehaviorAggregate {
    subjectDurations = subjectDurations == null ? List.of() : List.copyOf(subjectDurations);
  }

  /**
   * 주제 하나에 머문 시간이다.
   *
   * <p>세션 하나의 집계값에 주제 이름을 붙인 것이며 <b>합계가 아니다.</b> 두 값의 뜻과 한계는 {@link StrokeBehaviorSummary} 와 같다 —
   * {@code drawingDurationMs}는 중단 후 재개 구간을 제외한 추정값이고 {@code activeDrawingMs}는 실제 입력 시간의 합이다.
   *
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})
   * @param drawingDurationMs 그 주제에 머문 전체 경과 시간(ms)이며 집계하지 못했으면 {@code null}
   * @param activeDrawingMs 그 주제에서 실제로 획을 그린 시간의 합(ms)이며 집계하지 못했으면 {@code null}
   */
  public record SubjectDuration(
      String drawingSubject, Long drawingDurationMs, Long activeDrawingMs) {}
}
