package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 발달 맥락 문장의 검수 출처 식별자다.
 *
 * <p>한 관찰에 <strong>출처가 없는 것은 정상이다.</strong> AI 서버는 두 종류의 맥락 문장을 보낸다 — 검수 자료에서 온 연령 규준 문장은 출처를 달고,
 * 나이를 모르거나 그 도메인에 검수된 한국 규준이 없을 때 쓰는 '이번 활동에서만 살펴본다'는 문장은 애초에 규준을 주장하지 않아 출처가 없다. <strong>출처 없는
 * 규준 문장이 나가지 않는다는 보장은 등록부가 한다</strong> — 여기서는 받은 것을 그대로 보관하고, 화면은 출처가 있을 때만 밝힌다.
 *
 * <p>{@code domain} 으로 소유 관찰과 잇는다({@link ReportDiaryEvidenceRef} 와 같은 이유로 PK 대신 값으로 잇는다 — 부모와 자식을 한
 * 트랜잭션에서 함께 쓴다). 리포트 안에서 도메인은 유일하다.
 */
@Entity
@Table(name = "report_diary_development_sources")
public class ReportDiaryDevelopmentSource {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "domain", nullable = false, length = 30)
  private String domain;

  @Column(name = "source_id", nullable = false, length = 60)
  private String sourceId;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryDevelopmentSource() {}

  private ReportDiaryDevelopmentSource(
      Report report, String domain, String sourceId, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.domain = Objects.requireNonNull(domain, "domain must not be null");
    this.sourceId = Objects.requireNonNull(sourceId, "sourceId must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 검수 출처를 만든다.
   *
   * @param report 소속 리포트
   * @param domain 소유 관찰의 도메인
   * @param sourceId 검수 출처 식별자
   * @param displayOrder 관찰 안에서의 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryDevelopmentSource create(
      Report report, String domain, String sourceId, int displayOrder) {
    return new ReportDiaryDevelopmentSource(report, domain, sourceId, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 관찰의 도메인
   */
  public String getDomain() {
    return domain;
  }

  /**
   * @return 검수 출처 식별자
   */
  public String getSourceId() {
    return sourceId;
  }

  /**
   * @return 관찰 안에서의 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
