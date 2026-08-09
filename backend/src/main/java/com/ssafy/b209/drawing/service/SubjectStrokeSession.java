package com.ssafy.b209.drawing.service;

/**
 * 행동 집계 대상 세션 하나와 그 세션이 그린 주제다 (S15P11B209-975).
 *
 * <p>세션 식별자만 넘기던 집계 입력에 <b>주제 라벨</b>을 붙인 형태다. HTP 리포트는 집·나무·사람 세 활동을 함께 다루므로, 합계만으로는 "어느 그림에 더 오래
 * 머물렀는지"를 말할 수 없다. 주제를 함께 받아야 세션별 시간에 이름을 붙일 수 있다.
 *
 * <p>🔴 <b>주제 라벨의 출처를 잘못 고르면 세션이 조용히 빠진다.</b> 리포트 맥락의 {@code subjectContexts}는 서술·탐지 코드·문답이 모두 빈
 * 주제를 걸러낸 목록이라, <b>그리기만 하고 관찰·문답이 없는 세션이 그 목록에 없다.</b> 그것을 주제 매핑에 쓰면 실제로 그린 그림 하나가 주제별 시간에서 사라지고,
 * 남은 둘만으로 "가장 오래 머문 그림"이 정해진다 — 없는 관찰이 만들어진다. 필터링 <b>전</b>의 세션 목록을 쓴다({@code
 * ObservationGenerationContext.activitySessions}).
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})이며 그림일기·단독 세션은 {@code null}
 */
public record SubjectStrokeSession(Long drawingSessionId, String drawingSubject) {}
