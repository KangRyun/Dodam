package com.ssafy.b209.analysis.repository;

/**
 * 분석 입력으로 사용하지 못한 자료의 출처와 제외 사유다.
 *
 * @param sourceType 제외한 입력의 출처 유형
 * @param sourceId 제외한 입력의 출처 식별자이며 없으면 {@code null}
 * @param inputName 제외한 입력의 이름
 * @param reasonCode 외부에 노출해도 되는 제외 사유 코드
 * @param reasonDetail 원문과 개인정보를 포함하지 않는 제외 사유 설명
 * @param retryable 같은 입력으로 다시 시도할 수 있는지 여부
 */
public record UnusedAnalysisInput(
    String sourceType,
    Long sourceId,
    String inputName,
    String reasonCode,
    String reasonDetail,
    boolean retryable) {}
