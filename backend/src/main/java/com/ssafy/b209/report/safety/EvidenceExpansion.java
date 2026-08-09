package com.ssafy.b209.report.safety;

import java.util.Set;

/**
 * 카드 한 건의 근거를 말단까지 펼친 결과다.
 *
 * @param independentEvidenceCount 병합 상한을 적용한 뒤의 독립 근거 수
 * @param childExpressionPresent 말단 근거 중 아이 표현 근거가 하나 이상 있으면 {@code true}
 * @param issues 전개 과정에서 발견한 구조적 문제 사유이며 없으면 빈 집합
 */
public record EvidenceExpansion(
    int independentEvidenceCount,
    boolean childExpressionPresent,
    Set<InterpretationExclusionReason> issues) {}
