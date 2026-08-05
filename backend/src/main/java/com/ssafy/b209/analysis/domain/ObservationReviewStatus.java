package com.ssafy.b209.analysis.domain;

/**
 * 관찰 결과가 보호자에게 열릴 만큼 검토됐는지를 나타낸다.
 *
 * <p><b>사람 전문가 검토 워크플로는 이 서비스에 없다.</b> 그래서 값이 {@code AI_DRAFT} 하나뿐이던 동안 {@code
 * ObservationReportPersistenceService} 의 검토 통과 판정은 <b>구조적으로 항상 거짓</b>이었고, 그 결과 모든 관찰 특징이 {@code
 * EXPERT_ONLY} 로 저장돼 <b>아무에게도 도달하지 않았다</b>(운영 실측: {@code report_observed_features} 97건 전부 {@code
 * EXPERT_ONLY}). 읽는 쪽이 없는 데이터를 계속 생성하고 있었다는 뜻이다.
 *
 * <p>그래서 <b>AI 가 전문가 역할을 대신한다.</b> AI 가 스스로 생성한 초안을 별도 기준으로 재검토해 통과시키면 {@link #AI_REVIEWED} 를 실어
 * 보내고, 그 리포트의 관찰 특징만 보호자 공개 대상이 된다. 사람 전문가 워크플로가 생기면 그때 검토 상태를 추가하고 {@link #isReviewed()} 에 포함시키면
 * 된다 — 판정이 이 enum 한 곳에 모여 있는 이유다.
 *
 * <p>컬럼은 {@code analysis_observation_results.review_status VARCHAR(30)} 이고 {@code EnumType.STRING}
 * 으로 저장하므로 값을 늘려도 <b>스키마 변경이 없다.</b>
 */
public enum ObservationReviewStatus {
  /** AI 가 생성했을 뿐 어떤 검토도 거치지 않은 초안이다. 보호자 공개 대상이 아니다. */
  AI_DRAFT,

  /**
   * AI 자체 검토를 통과해 보호자에게 열 수 있는 상태다.
   *
   * <p>사람 전문가가 본 것이 아니다. 리포트에는 진단이 아님을 알리는 한계 고지가 그대로 붙는다(CLAUDE.md 9절).
   */
  AI_REVIEWED;

  /**
   * 보호자 공개 판정에 쓰는 "검토를 통과했는가"다.
   *
   * <p>초안이 아니면 통과로 본다. 사람 전문가 검토 상태가 나중에 추가돼도 이 규칙이 그대로 성립한다.
   *
   * @return 초안이 아니면 {@code true}
   */
  public boolean isReviewed() {
    return this != AI_DRAFT;
  }

  /**
   * AI 가 보낸 검토 상태 문자열을 안전하게 해석한다.
   *
   * <p>모르는 값·{@code null} 은 {@link #AI_DRAFT} 로 떨어뜨린다. 해석하지 못한 값을 통과로 취급하면 검토받지 않은 관찰이 보호자에게 열린다 —
   * 실패 방향은 항상 닫히는 쪽이어야 한다.
   *
   * @param value AI 응답의 검토 상태 문자열이며 없으면 {@code null}
   * @return 해석된 검토 상태이며 해석할 수 없으면 {@link #AI_DRAFT}
   */
  public static ObservationReviewStatus fromAiStatus(String value) {
    if (value == null) {
      return AI_DRAFT;
    }
    for (ObservationReviewStatus status : values()) {
      if (status.name().equals(value)) {
        return status;
      }
    }
    return AI_DRAFT;
  }
}
