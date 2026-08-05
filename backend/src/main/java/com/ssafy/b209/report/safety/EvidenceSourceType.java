package com.ssafy.b209.report.safety;

/**
 * 근거 항목의 종류다(875 계약 §4 {@code evidenceItems[].sourceType}).
 *
 * <p><strong>독립 근거 수를 이 종류로 세지 않는다.</strong> 종류로 세면 같은 답변 하나를 두 종류로 신고해 2건을 만들 수 있고, 반대로 서로 다른 답변 두
 * 건이 1건으로 깎인다. 독립성은 말단 {@link EvidenceSourceRef} 단위로 판정한다(보호자 계약 §4-1 조건 1).
 *
 * <p>값 집합은 저장 계층의 {@code ReportEvidenceSourceType}(S15P11B209-900)과 같다. 두 벌이 존재하는 이유와 정리 계획은 {@link
 * IndependentEvidenceCounter} 문서를 참고한다.
 */
public enum EvidenceSourceType {
  /** 그림에서 확인한 관찰이다. 아이 표현 근거가 아니다. */
  VISION,
  /** 아이의 답변이다. 아이 표현 근거다. */
  CHILD_ANSWER,
  /** 아이가 고른 감정 코드다. 아이 표현 근거이며 감정 묶음으로 병합된다. */
  SELECTED_EMOTION,
  /** 아이가 말한 감정 텍스트다. 아이 표현 근거이며 감정 묶음으로 병합된다. */
  STATED_EMOTION,
  /** 활동 기록 지표다. 아이 표현 근거가 아니며 지표 묶음으로 병합된다. */
  ACTIVITY_METRIC,
  /** 여러 그림에서 반복된 주제로, 원본에서 파생된 근거다. */
  REPEATED_SUBJECT,
  /** 이전 활동에서도 반복된 관찰로, 원본에서 파생된 근거다. */
  LONGITUDINAL;

  /**
   * 아이 자신의 확인 가능한 표현 근거인지 판단한다.
   *
   * <p>아이 표현 요건의 <strong>주 판정 축은 말단 참조의 {@link EvidenceSourceKind#isChildExpression()
   * kind}</strong>다. 이 종류 검사는 그와 OR로 묶이는 보조 축이며, 파생 근거({@link #REPEATED_SUBJECT}·{@link
   * #LONGITUDINAL})에는 걸리지 않는다 — 파생 근거의 아이 표현 여부는 펼친 말단으로만 결정된다. 정상 데이터에서는 두 축의 결론이 같다({@code
   * CHILD_ANSWER}·{@code STATED_EMOTION}은 {@code QA_ANSWER}에서, {@code SELECTED_EMOTION}은 {@code
   * EMOTION_SELECTION}에서 온다).
   *
   * @return 아이 표현 근거면 {@code true}
   */
  public boolean isChildExpression() {
    return this == CHILD_ANSWER || this == SELECTED_EMOTION || this == STATED_EMOTION;
  }

  /**
   * 이 종류가 속한 병합 묶음을 돌려준다.
   *
   * @return 병합 묶음이며 병합 대상이 아니면 {@code null}
   */
  public EvidenceMergeFamily mergeFamily() {
    return switch (this) {
      case SELECTED_EMOTION, STATED_EMOTION -> EvidenceMergeFamily.EMOTION;
      case ACTIVITY_METRIC -> EvidenceMergeFamily.ACTIVITY_METRIC;
      default -> null;
    };
  }

  /**
   * 계약 코드값을 근거 종류로 해석한다.
   *
   * @param code 계약 코드값이며 없으면 {@code null}
   * @return 해석된 근거 종류이며 해석할 수 없으면 {@code null}
   */
  public static EvidenceSourceType fromCode(String code) {
    if (code == null || code.isBlank()) {
      return null;
    }
    try {
      return valueOf(code.trim());
    } catch (IllegalArgumentException exception) {
      return null;
    }
  }
}
