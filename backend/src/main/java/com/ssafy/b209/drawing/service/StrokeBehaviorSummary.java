package com.ssafy.b209.drawing.service;

import java.util.Set;

/**
 * 저장된 Stroke 배치에서 집계한 그리기 과정 요약이다 (S15P11B209-772).
 *
 * <p>AI 계약 Type을 그대로 쓰지 않고 별도 Record를 두는 이유는 계층 방향 때문이다. 그림 도메인이 AI 요청 계약({@code
 * infrastructure.ai.drawing.contract})을 import하면 계약이 바뀔 때마다 도메인이 흔들린다. 계약으로의 변환은 AI 어댑터가 담당한다.
 *
 * <p>필드 Type이 모두 Wrapper인 것은 <b>장차</b> 측정 불가능한 값이 생겼을 때 0이 아니라 {@code null}로 내보내기 위해서다. 없는 데이터를 0으로
 * 채우면 AI가 "0회"라는 관찰 결과로 읽는다. 다만 <b>현재 집계기는 측정값 전부를 항상 구체값으로 채우며 {@code null}을 만드는 실행 경로가 없다.</b>
 * {@code null}이 실제로 생기는 곳은 {@link StrokeBehaviorSummaryService#merge} 뿐이다 — 한 세션이라도 모르는 값이 섞이면 그
 * 항목의 합계를 {@code null}로 남긴다.
 *
 * <p><b>횟수 넷은 출처가 두 가지다.</b> 앱이 {@code PAUSE}·{@code ERASE}·{@code TOOL_CHANGE}·{@code
 * COLOR_CHANGE} 명시 이벤트를 보낸 세션에서는 <b>그 이벤트를 센 정확한 값</b>이고, 보내지 않은 세션에서는 {@code STROKE} 속성 변화·배치 경계
 * 시각으로 <b>추론한 값</b>이다. 둘을 함께 세지 않는 이유와 판정 규칙은 {@link StrokeBehaviorSummaryService} javadoc 에 있다. 값만
 * 보고는 어느 쪽인지 알 수 없으므로, 쓰는 쪽은 어느 경우에도 <b>단정적인 관찰</b>로 옮기지 말아야 한다.
 *
 * @param drawingDurationMs 그림 전체 경과 시간이며 중단 후 재개 구간은 제외한 추정값
 * @param activeDrawingMs 실제로 획을 그린 시간의 합
 * @param strokeCount 그은 획의 수다 (S15P11B209-975). <b>지우개 획도 포함한다</b> — 지우개로 긋는 것도 획이고, 세는 대상을 도구로 가르면
 *     "전체 획 수"가 아니게 된다. 그래서 {@code eraseCount} 와 <b>세는 대상이 겹치며</b>, 두 값으로 지우기 비율 같은 파생 수치를 만들면 안
 *     된다. 계약이 파생 필드를 싣지 않는 이유가 이것이다
 * @param pauseCount 멈춤 횟수. {@code PAUSE} 이벤트를 받은 세션은 정확한 값이고, 아니면 배치 경계 추정값이라 상한도 하한도 아니다
 * @param undoCount 실행 취소 횟수. {@code UNDO} 이벤트만 세며 {@code REDO} 로 상계하지 않는다
 * @param eraseCount 지우기 횟수. {@code ERASE} 이벤트를 받은 세션은 그 이벤트만, 아니면 {@code tool=ERASER} 획을 센다
 * @param toolChangeCount 도구를 바꾼 횟수. {@code TOOL_CHANGE} 이벤트를 받은 세션은 그 이벤트만, 아니면 획의 도구 변화를 센다
 * @param colorChangeCount 색을 바꾼 횟수. {@code COLOR_CHANGE} 이벤트를 받은 세션은 그 이벤트만, 아니면 획의 색 변화를 센다
 * @param colorsUsed 실제로 획을 그린 색의 <b>집합</b>이며 소문자로 정규화돼 있다 (S15P11B209-975). <b>내부 표현이고 AI 계약에는
 *     가짓수({@code colorsUsedCount})만 나간다</b> — 색 코드 자체는 관찰 재료가 아니고, 집합이어야 여러 세션을 합칠 때 <b>합집합</b>으로 셀
 *     수 있다. 세션별 가짓수를 더하면 세 장에 모두 쓴 빨강이 3가지로 계수된다. {@code null} 은 집계하지 못했다는 뜻이고 빈 집합은 색을 쓴 획이 없었다는
 *     관찰 사실이다
 * @param pressureAvailable 필압 데이터가 실제로 저장돼 있는지 여부
 * @param truncated 배치 수 상한에 걸려 세션 앞부분만 집계했는지 여부. {@code true}면 위 값 전부가 부분 집계다
 */
public record StrokeBehaviorSummary(
    Long drawingDurationMs,
    Long activeDrawingMs,
    Integer strokeCount,
    Integer pauseCount,
    Integer undoCount,
    Integer eraseCount,
    Integer toolChangeCount,
    Integer colorChangeCount,
    Set<String> colorsUsed,
    boolean pressureAvailable,
    boolean truncated) {

  /**
   * 색 집합을 불변으로 복사한다.
   *
   * <p>{@code null}은 {@code null}로 남긴다 — "집계하지 못함"과 "색을 쓴 획이 없음"(빈 집합)은 다른 뜻이라, 여기서 빈 집합으로 바꾸면 집계
   * 실패가 "0가지 색을 썼다"는 관찰 사실로 둔갑한다. Wrapper Type 을 쓰는 것과 같은 원칙이다.
   */
  public StrokeBehaviorSummary {
    colorsUsed = colorsUsed == null ? null : Set.copyOf(colorsUsed);
  }
}
