package com.ssafy.b209.report.dto;

import java.util.List;

/**
 * HTP 주제(집·나무·사람) 하나의 관찰 묶음이다 (875 §5).
 *
 * <p>순서는 {@code HOUSE → TREE → PERSON}을 보장한다. HTP 가 아닌 활동은 이 목록이 비거나 전체 그림 한 건이다.
 *
 * <p>{@code interpretationRefs}는 <strong>같은 응답의 {@code publicInterpretations} 배열
 * 인덱스</strong>다({@code category} 가 아니다). 리포트 버전 스냅샷 안에서 배열 순서를 재정렬하면 참조가 조용히 다른 카드를 가리킨다(875 §5-1).
 *
 * @param subjectType 주제({@code HOUSE|TREE|PERSON})이며 그림일기는 {@code null}
 * @param imageUrl 완성 그림 조회 URL 이며 없으면 {@code null}
 * @param visionObservations 눈으로 확인된 관찰 서술 목록
 * @param qaPairs 이 주제에서 나눈 문답 목록
 * @param interpretationRefs 이 주제와 연결된 경향 해석 카드의 배열 인덱스 목록
 */
public record ReportSubjectResponse(
    String subjectType,
    String imageUrl,
    List<String> visionObservations,
    List<ReportQaPairResponse> qaPairs,
    List<Integer> interpretationRefs) {}
