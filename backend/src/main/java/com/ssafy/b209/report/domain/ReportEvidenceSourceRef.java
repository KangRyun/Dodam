package com.ssafy.b209.report.domain;

import java.util.Objects;

/**
 * 서버가 발급한 원본 근거 참조 한 건이다.
 *
 * <p>독립 근거 계수의 단위이며, 같은 {@code kind}·{@code id} 는 몇 번 참조돼도 1건으로 센다. 그래서 값 동등성이 필요해 record 로 둔다.
 *
 * @param kind 원본 근거의 종류
 * @param id 서버가 발급한 식별자이며 조합키는 허용하지 않는다
 */
public record ReportEvidenceSourceRef(ReportEvidenceSourceKind kind, String id) {

  /** 두 값이 모두 있어야 해석 가능한 참조가 된다. */
  public ReportEvidenceSourceRef {
    Objects.requireNonNull(kind, "kind must not be null");
    if (id == null || id.isBlank()) {
      throw new IllegalArgumentException("id must not be blank");
    }
  }
}
