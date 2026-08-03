package com.ssafy.b209.drawing.service;

/**
 * 저장된 Stroke 배치에서 집계한 그리기 과정 요약이다 (S15P11B209-772).
 *
 * <p>AI 계약 Type을 그대로 쓰지 않고 별도 Record를 두는 이유는 계층 방향 때문이다. 그림 도메인이 AI 요청 계약({@code
 * infrastructure.ai.drawing.contract})을 import하면 계약이 바뀔 때마다 도메인이 흔들린다. 계약으로의 변환은 AI 어댑터가 담당한다.
 *
 * <p>필드 Type이 모두 Wrapper인 것은 <b>장차</b> 측정 불가능한 값이 생겼을 때 0이 아니라 {@code null}로 내보내기 위해서다. 없는 데이터를 0으로
 * 채우면 AI가 "0회"라는 관찰 결과로 읽는다. 다만 <b>현재 집계기는 8개 값을 항상 구체값으로 채우며 {@code null}을 만드는 실행 경로가 없다.</b>
 *
 * @param drawingDurationMs 그림 전체 경과 시간이며 중단 후 재개 구간은 제외한 추정값
 * @param activeDrawingMs 실제로 획을 그린 시간의 합
 * @param pauseCount 멈춤 횟수의 추정값이며 상한도 하한도 아니다
 * @param undoCount 실행 취소 횟수
 * @param eraseCount 지우기 횟수
 * @param toolChangeCount 도구를 바꾼 횟수
 * @param colorChangeCount 색을 바꾼 횟수
 * @param pressureAvailable 필압 데이터가 실제로 저장돼 있는지 여부
 * @param truncated 배치 수 상한에 걸려 세션 앞부분만 집계했는지 여부. {@code true}면 위 값 전부가 부분 집계다
 */
public record StrokeBehaviorSummary(
    Long drawingDurationMs,
    Long activeDrawingMs,
    Integer pauseCount,
    Integer undoCount,
    Integer eraseCount,
    Integer toolChangeCount,
    Integer colorChangeCount,
    boolean pressureAvailable,
    boolean truncated) {}
