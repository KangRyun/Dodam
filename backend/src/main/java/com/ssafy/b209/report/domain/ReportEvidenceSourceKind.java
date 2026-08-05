package com.ssafy.b209.report.domain;

/**
 * 원본 근거를 가리키는 참조의 종류다.
 *
 * <p>참조 식별자는 <strong>서버가 발급한 값만</strong> 쓴다. 조합키를 허용하면 생성자가 스스로 식별자를 만들 수 있어 "서로 독립된 근거 2건" 검증이 자기
 * 신고로 무력해진다(계약 §4).
 */
public enum ReportEvidenceSourceKind {
  /** 답변 메시지 식별자다. */
  QA_ANSWER,
  /** 탐지 객체 행 식별자다. */
  DETECTED_OBJECT,
  /** 관찰 서술(analysis_observation_results) 행 식별자다. */
  VLM_OBSERVATION,
  /** 선택 감정(drawing_session_emotions) 행 식별자다. */
  EMOTION_SELECTION,
  /** 서버가 발급한 활동 지표 스냅샷 식별자다. */
  ACTIVITY_METRIC,
  /**
   * 이전 활동의 원본 관찰 레코드 또는 확인된 아동 표현 메시지 식별자다.
   *
   * <p>이전 AI 해석 결과를 가리켜서는 안 된다 — 자기 해석이 자기 근거가 되는 순환 추론이 된다.
   */
  PRIOR_ACTIVITY
}
