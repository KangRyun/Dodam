package com.ssafy.b209.report.safety;

import java.util.List;

/**
 * 표현 안전 필터가 카드 한 건을 검사한 결과다.
 *
 * <p>{@code matchedPatterns}는 <strong>정규식 패턴 문자열</strong>이며 원문 조각이 아니다. 카드 문장에는 아이 표현이 섞일 수 있어 원문을
 * 로그에 남기지 않기 때문이다(AI 측 {@code ai/report_safety.py}와 같은 가드레일).
 *
 * @param safe 격리 대상 표현이 없으면 {@code true}
 * @param matchedPatterns 매칭된 패턴 문자열 목록이며 안전하면 빈 목록
 */
public record ExpressionVerdict(boolean safe, List<String> matchedPatterns) {}
