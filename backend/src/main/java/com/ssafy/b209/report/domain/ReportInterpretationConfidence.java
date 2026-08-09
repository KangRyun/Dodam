package com.ssafy.b209.report.domain;

/**
 * 경향 해석 카드가 인용한 근거의 <strong>종류</strong>로 계산한 확신 등급이다 (S15P11B209-982).
 *
 * <p>LLM 이 스스로 매기는 점수가 아니다. AI 쪽 <strong>코드</strong>가 카드의 {@code evidenceRefs} 가 어떤 종류의 근거를
 * 가리키는지 보고 결정한다({@code ai/interpretation_gate.confidence_for}) — 모델에게 "얼마나 확신하냐"고 물으면 근거가
 * 약한 해석도 STRONG 이라 주장해 등급 체계 전체가 장식이 된다.
 *
 * <p>⚠️ 아래 판정 규칙의 정본은 {@code docs/S15P11B209-875-report-api-contract.md} <strong>§3-1</strong> 이고,
 * 실제 계산은 AI 쪽에 있다. BE 는 계산하지 않고 받아 적기만 한다 — 이 주석과 AI 구현이 갈리면 AI 쪽이 맞다.
 *
 * <p>등급은 보호자에게 "이 카드를 얼마나 무겁게 읽어야 하는지"를 알리는 표시이며 <strong>진단의 강도가 아니다.</strong> 아이를 평가한
 * 점수도 아니다 — {@code WEAK} 는 "아이가 낮다"가 아니라 "근거가 이만큼"이라는 뜻이라, 보호자 금지 항목인 '점수·등급'에
 * 해당하지 않는다({@code docs/api/report-detail-guardian-contract.md} §4-1).
 *
 * <p>등급이 없다고 카드를 버리지 않는다 — 등급은 <strong>선택</strong>이고 없으면 화면에 표시하지 않을 뿐이다. 필수로 만들면
 * AI 가 등급 이름을 하나 바꿨을 때 보호자 리포트가 통째로 실패한다(836 재발).
 *
 * <p>⚠️ 판정은 근거의 <strong>개수를 보지 않는다.</strong> 약한 근거를 여러 개 모아 등급을 올리는 길을 막기 위한 것이다 —
 * 지표를 합산해 경향을 만드는 것이 그림 심리 해석이 실제로 무너진 경로다.
 */
public enum ReportInterpretationConfidence {
  /** 아이가 직접 한 말이 근거이고, 그림·활동 지표는 섞이지 않았다. 해석이 아이 발화 위에 바로 얹혀 있다. */
  STRONG,
  /** 아이가 한 말에 그림이나 활동 지표를 이어 붙인 해석이다. 아이가 말하지 않은 것을 한 걸음 미뤄 짐작했다. */
  MODERATE,
  /** 근거에 아이가 한 말이 없다. 그림 단독·활동 지표 단독이거나, 아이 표현이라도 고른 것(감정 칩·선택형 답변)뿐이다(994). */
  WEAK
}
