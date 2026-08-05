package com.ssafy.b209.report.safety;

/**
 * 표현 안전 필터(2단)가 카드를 <strong>강등</strong>한 사유다.
 *
 * <p><strong>{@link InterpretationExclusionReason}과 별 타입으로 둔 이유:</strong> 두 실패의 성질이 다르다. 제외는 근거 자체가
 * 없어 표현을 다듬어도 공개 대상이 아니고({@code WITHHELD}), 강등은 내용에 가치가 있어 전문가 검토로 돌리는 것이다({@code EXPERT_ONLY}). 한
 * enum에 섞으면 "검토해도 공개할 수 없는 사유"가 검토 대기열의 사유 목록에 들어가고, 호출부가 두 갈래를 구분하지 않고 처리해도 컴파일이 통과한다. 타입을 갈라 두면 그
 * 혼동이 컴파일 단계에서 막힌다.
 *
 * <p><strong>값이 하나인 이유:</strong> 강등 판정은 정규식 38개(질환명 28 · 진단 단정 5 · 과잉 추론 5)의 OR이고, 그 38개를 보호자·전문가에게
 * 의미 있는 분류로 묶는 체계가 AI({@code ai/report_safety.py})에 없다. 여기서 분류를 새로 발명하면 근거 없는 체계가 저장 데이터에 굳는다. 그래서
 * "표현 필터에 걸렸다"는 사실만 코드로 남기고, 어떤 패턴이었는지는 <strong>로그로만</strong> 남긴다.
 *
 * <p>저장 계층(S15P11B209-900)의 {@code report_public_interpretations.withheld_reason_code}가 {@code
 * VARCHAR(40)}이고 {@code disclosure_state <> 'PUBLISHED'}면 NOT NULL을 요구한다(V37). 강등도 그 CHECK 대상이므로 이
 * 값이 없으면 저장할 수 없다.
 */
public enum InterpretationDemotionReason {
  /** 보호자에게 나갈 문장에 진단 단정·질환명·감정 과잉 추론 표현이 있었다. 내용은 보존하고 전문가 검토로 돌린다. */
  EXPRESSION_FILTER_BLOCKED
}
