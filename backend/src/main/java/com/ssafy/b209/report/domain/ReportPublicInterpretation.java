package com.ssafy.b209.report.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * 보호자에게 노출할 수 있는 비진단 경향 해석 카드 한 건이다.
 *
 * <p>이 Entity는 {@code report_observed_features}와 <strong>다른 경로</strong>다. 관찰 특징 쪽은 {@code
 * ObservationReportPersistenceService.resolveVisibility()}가 전문가 검토 전 항목을 전부 {@link
 * ReportFeatureVisibility#EXPERT_ONLY}로 강등하고, 그 판단에 쓰이는 검토 상태는 전이 경로가 없어 항상 미검토다. 경향 해석을 그 경로에 실으면
 * 구현이 끝나도 보호자 화면에는 아무것도 나오지 않는다(계약 §4-2 결정 1). 그래서 공개 여부를 이 Entity가 직접 들고 있다.
 *
 * <p>{@code displayOrder}는 응답 배열의 인덱스이자 {@code interpretationRefs}가 가리키는 대상이다. <strong>리포트 버전 스냅샷
 * 안에서 순서를 재정렬하면</strong> 참조가 조용히 다른 카드를 가리킨다. 재생성은 새 리포트 버전을 만들므로 버전 간 순서 변화는 무해하다.
 */
@Entity
@Table(name = "report_public_interpretations")
public class ReportPublicInterpretation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Enumerated(EnumType.STRING)
  @Column(name = "category", nullable = false, length = 20)
  private ReportInterpretationCategory category;

  @Column(name = "title", nullable = false, length = 200)
  private String title;

  @Column(name = "tendency_text", nullable = false, columnDefinition = "TEXT")
  private String tendencyText;

  @Column(name = "scope_text", columnDefinition = "TEXT")
  private String scopeText;

  @Column(name = "home_observation_guide", columnDefinition = "TEXT")
  private String homeObservationGuide;

  @Enumerated(EnumType.STRING)
  @Column(name = "disclosure_state", nullable = false, length = 20)
  private ReportInterpretationDisclosureState disclosureState;

  @Column(name = "withheld_reason_code", length = 40)
  private String withheldReasonCode;

  @OneToMany(
      mappedBy = "interpretation",
      cascade = CascadeType.ALL,
      orphanRemoval = true,
      fetch = FetchType.LAZY)
  @OrderBy("displayOrder ASC")
  private List<ReportInterpretationEvidence> evidences = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportPublicInterpretation() {}

  private ReportPublicInterpretation(
      Report report,
      int displayOrder,
      ReportInterpretationCategory category,
      String title,
      String tendencyText,
      String scopeText,
      String homeObservationGuide) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.category = Objects.requireNonNull(category, "category must not be null");
    this.title = requireText(title, "title");
    this.tendencyText = requireText(tendencyText, "tendencyText");
    this.scopeText = scopeText;
    this.homeObservationGuide = homeObservationGuide;
    // 공개는 두 단 검증을 통과해야 얻는 상태다. 기본값을 공개로 두면 검증을 건너뛴 카드가 노출된다.
    this.disclosureState = ReportInterpretationDisclosureState.WITHHELD;
    this.withheldReasonCode = PENDING_VERIFICATION;
  }

  /** 아직 검증을 거치지 않아 보류 중임을 나타내는 사유 코드다. */
  public static final String PENDING_VERIFICATION = "PENDING_VERIFICATION";

  /**
   * 검증 전 상태(보류)의 경향 해석 카드를 생성한다.
   *
   * <p>생성 직후에는 항상 보류다. 공개는 {@link #publish()}로만 얻는다 — 기본값을 공개로 두면 검증을 통과하지 않은 카드가 노출된다.
   *
   * @param report 카드가 속한 리포트
   * @param displayOrder 0부터 시작하는 노출 순서이며 {@code interpretationRefs}가 가리키는 값이다
   * @param category 관찰 관점 라벨
   * @param title 카드 제목
   * @param tendencyText 가능성 어조의 경향 문장
   * @param scopeText 해석 범위 안내이며 없으면 {@code null}
   * @param homeObservationGuide 가정에서 살펴볼 점이며 없으면 {@code null}
   * @return 보류 상태의 경향 해석 카드
   * @throws IllegalArgumentException 순서가 음수이거나 제목·경향 문장이 빈 경우
   */
  public static ReportPublicInterpretation create(
      Report report,
      int displayOrder,
      ReportInterpretationCategory category,
      String title,
      String tendencyText,
      String scopeText,
      String homeObservationGuide) {
    return new ReportPublicInterpretation(
        report, displayOrder, category, title, tendencyText, scopeText, homeObservationGuide);
  }

  /**
   * 카드가 참조하는 근거를 연결한다.
   *
   * <p>같은 근거를 두 번 연결하지 않는다 — 독립 근거 계수가 중복 참조로 부풀는 것을 막는다.
   *
   * @param evidenceItem 연결할 근거
   * @throws IllegalArgumentException 이미 연결된 근거인 경우
   */
  public void referenceEvidence(ReportEvidenceItem evidenceItem) {
    Objects.requireNonNull(evidenceItem, "evidenceItem must not be null");
    boolean duplicated =
        evidences.stream().anyMatch(link -> link.getEvidenceItem().equals(evidenceItem));
    if (duplicated) {
      throw new IllegalArgumentException("evidence already referenced");
    }
    evidences.add(ReportInterpretationEvidence.create(this, evidences.size(), evidenceItem));
  }

  /**
   * 두 단 검증을 통과한 카드를 공개 상태로 올린다.
   *
   * @throws IllegalStateException 참조하는 근거가 없는 경우
   */
  public void publish() {
    if (evidences.isEmpty()) {
      throw new IllegalStateException("interpretation without evidence must not be published");
    }
    this.disclosureState = ReportInterpretationDisclosureState.PUBLISHED;
    this.withheldReasonCode = null;
  }

  /**
   * 구조적 공개 게이트에서 탈락한 카드를 보류로 표시한다.
   *
   * <p>강등이 아니다 — 근거 자체가 없으므로 표현을 다듬어도 공개 대상이 되지 않는다.
   *
   * @param reasonCode 탈락 사유 코드
   */
  public void withhold(String reasonCode) {
    this.disclosureState = ReportInterpretationDisclosureState.WITHHELD;
    this.withheldReasonCode = requireText(reasonCode, "reasonCode");
  }

  /**
   * 표현 안전 필터에서 걸린 카드를 전문가 검토로 돌린다. 내용은 지우지 않는다.
   *
   * @param reasonCode 강등 사유 코드
   */
  public void restrictToExpert(String reasonCode) {
    this.disclosureState = ReportInterpretationDisclosureState.EXPERT_ONLY;
    this.withheldReasonCode = requireText(reasonCode, "reasonCode");
  }

  /**
   * @return 경향 해석 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 0부터 시작하는 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 관찰 관점 라벨
   */
  public ReportInterpretationCategory getCategory() {
    return category;
  }

  /**
   * @return 카드 제목
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 가능성 어조의 경향 문장
   */
  public String getTendencyText() {
    return tendencyText;
  }

  /**
   * @return 해석 범위 안내이며 없으면 {@code null}
   */
  public String getScopeText() {
    return scopeText;
  }

  /**
   * @return 가정에서 살펴볼 점이며 없으면 {@code null}
   */
  public String getHomeObservationGuide() {
    return homeObservationGuide;
  }

  /**
   * @return 공개 판정 결과
   */
  public ReportInterpretationDisclosureState getDisclosureState() {
    return disclosureState;
  }

  /**
   * @return 미공개·강등 사유 코드이며 공개 상태면 {@code null}
   */
  public String getWithheldReasonCode() {
    return withheldReasonCode;
  }

  /**
   * @return 카드가 참조하는 근거 연결 목록
   */
  public List<ReportInterpretationEvidence> getEvidences() {
    return Collections.unmodifiableList(evidences);
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
