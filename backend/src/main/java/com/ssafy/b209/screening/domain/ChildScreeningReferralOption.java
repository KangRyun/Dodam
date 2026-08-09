package com.ssafy.b209.screening.domain;

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
 * 결과에 적힌 후속 상담 경로 한 줄이다.
 *
 * <p>결과 자체가 아니라 <strong>다음 걸음</strong>을 담는다. 선별 양성은 진단이 아니고 후속 진료·면담·검사가 필요하므로, 결과만 보여 주고 어디로 가면
 * 되는지 알려 주지 않으면 보호자는 결과를 결론으로 읽는다.
 */
@Entity
@Table(name = "child_screening_referral_options")
public class ChildScreeningReferralOption {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "screening_record_id", nullable = false)
  private ChildScreeningRecord screeningRecord;

  @Column(name = "referral_option", nullable = false, length = 120)
  private String referralOption;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ChildScreeningReferralOption() {}

  private ChildScreeningReferralOption(
      ChildScreeningRecord screeningRecord, String referralOption, int displayOrder) {
    this.screeningRecord =
        Objects.requireNonNull(screeningRecord, "screeningRecord must not be null");
    this.referralOption = Objects.requireNonNull(referralOption, "referralOption must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 후속 상담 경로를 만든다.
   *
   * @param screeningRecord 소속 선별 결과 기록
   * @param referralOption 소아청소년과·발달클리닉 등
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ChildScreeningReferralOption create(
      ChildScreeningRecord screeningRecord, String referralOption, int displayOrder) {
    return new ChildScreeningReferralOption(screeningRecord, referralOption, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소속 기록 식별자. 지연 로딩 Proxy에서도 식별자만 읽으므로 추가 조회가 없다
   */
  public Long getScreeningRecordId() {
    return screeningRecord.getId();
  }

  /**
   * @return 후속 상담 경로
   */
  public String getReferralOption() {
    return referralOption;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
