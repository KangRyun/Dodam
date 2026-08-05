package com.ssafy.b209.report.dto;

import java.util.List;

/**
 * 보호자에게 공개하는 경향 해석 카드 한 건이다 (875 §3).
 *
 * <p>공개 판정을 통과한 카드만 이 응답에 담는다 — 제외·강등 카드는 저장돼 있어도 여기에 실리지 않는다(계약 §4-1·§4-3).
 *
 * <p>FE 는 {@code tendencyText}를 단독으로 크게 표시하지 않고 근거와 {@code scopeText}를 항상 함께 보여준다. 그래서 이 세 값은 함께
 * 나가야 의미가 성립한다.
 *
 * @param category 관찰 관점 라벨
 * @param title 카드 제목
 * @param tendencyText 가능성 어조의 경향 문장
 * @param scopeText 해석 범위 안내
 * @param homeObservationGuide 가정에서 살펴볼 점
 * @param evidenceRefs 근거 번호 목록이며 {@code evidenceItems[].evidenceId}를 가리킨다
 */
public record ReportPublicInterpretationResponse(
    String category,
    String title,
    String tendencyText,
    String scopeText,
    String homeObservationGuide,
    List<Integer> evidenceRefs) {}
