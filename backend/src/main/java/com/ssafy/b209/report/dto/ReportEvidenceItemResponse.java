package com.ssafy.b209.report.dto;

/**
 * 경향 해석 카드가 참조하는 근거 한 건이다 (875 §4).
 *
 * <p>최상위 배열로 나간다 — 카드가 {@code evidenceRefs}로 이 번호를 가리키고, 여러 카드가 같은 근거를 재사용할 수 있다.
 *
 * <p>내부 검증에 쓰는 원본 참조({@code sourceRef}·{@code derivedFrom})는 응답에 담지 않는다. 보호자 화면에 필요하지 않고, 서버가 발급한 행
 * 식별자를 외부로 흘리지 않는다.
 *
 * @param evidenceId 리포트 안에서 유일한 근거 번호이며 화면에 노출하지 않는다
 * @param sourceType 근거 종류이며 화면에는 코드가 아니라 라벨로 표시된다
 * @param text 근거 문장
 */
public record ReportEvidenceItemResponse(int evidenceId, String sourceType, String text) {}
