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
 * 그림일기 V2 구조화 항목이 가리키는 근거 참조다.
 *
 * <p>핵심 이야기·흐름 단계·이번 활동 관찰·보호자 질문이 모두 같은 모양의 참조를 갖는다. 종류마다 표를 만들면 두 컬럼짜리 표가 넷이 되므로 {@code
 * ownerType} 으로 갈라 한 표에 모은다.
 *
 * <p>{@code ownerOrder} 는 소유 항목의 {@code displayOrder} 다. 자식 행의 PK 를 참조하지 않는 이유는 저장 순서 때문이다 — 부모와
 * 자식을 같은 트랜잭션에서 한꺼번에 쓰는데 PK 로 묶으면 부모를 먼저 flush 해 식별자를 받아야 한다. 리포트 안에서만 쓰는 표시용 묶음이라 순서로 잇는 편이 단순하다.
 * 1:1 인 {@code STORY_SNAPSHOT} 은 0 이다.
 */
@Entity
@Table(name = "report_diary_evidence_refs")
public class ReportDiaryEvidenceRef {

  /** 핵심 이야기 — 리포트당 하나라 {@code ownerOrder} 는 언제나 0 이다. */
  public static final String OWNER_STORY_SNAPSHOT = "STORY_SNAPSHOT";

  /** 이야기 흐름 단계. */
  public static final String OWNER_NARRATIVE_STEP = "NARRATIVE_STEP";

  /** 이번 활동에서 확인된 표현. */
  public static final String OWNER_SESSION_OBSERVATION = "SESSION_OBSERVATION";

  /** 보호자가 이어 갈 질문. */
  public static final String OWNER_CAREGIVER_QUESTION = "CAREGIVER_QUESTION";

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "owner_type", nullable = false, length = 30)
  private String ownerType;

  @Column(name = "owner_order", nullable = false, columnDefinition = "SMALLINT")
  private int ownerOrder;

  @Column(name = "ref_kind", nullable = false, length = 40)
  private String refKind;

  @Column(name = "ref_id", nullable = false, length = 64)
  private String refId;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryEvidenceRef() {}

  private ReportDiaryEvidenceRef(
      Report report,
      String ownerType,
      int ownerOrder,
      String refKind,
      String refId,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.ownerType = Objects.requireNonNull(ownerType, "ownerType must not be null");
    this.ownerOrder = ownerOrder;
    this.refKind = Objects.requireNonNull(refKind, "refKind must not be null");
    this.refId = Objects.requireNonNull(refId, "refId must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 근거 참조를 만든다.
   *
   * @param report 소속 리포트
   * @param ownerType 소유 항목 종류
   * @param ownerOrder 소유 항목의 노출 순서이며 1:1 항목은 0
   * @param refKind 근거 종류
   * @param refId BE 가 발급한 근거 식별자
   * @param displayOrder 항목 안에서의 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryEvidenceRef create(
      Report report,
      String ownerType,
      int ownerOrder,
      String refKind,
      String refId,
      int displayOrder) {
    return new ReportDiaryEvidenceRef(report, ownerType, ownerOrder, refKind, refId, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 항목 종류
   */
  public String getOwnerType() {
    return ownerType;
  }

  /**
   * @return 소유 항목의 노출 순서
   */
  public int getOwnerOrder() {
    return ownerOrder;
  }

  /**
   * @return 근거 종류
   */
  public String getRefKind() {
    return refKind;
  }

  /**
   * @return 근거 식별자
   */
  public String getRefId() {
    return refId;
  }

  /**
   * @return 항목 안에서의 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
