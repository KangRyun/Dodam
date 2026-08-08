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
 * 선별 결과의 영역별 라벨 한 줄이다.
 *
 * <p><strong>점수가 아니라 라벨만</strong> 담는다. 원점수·규준점수는 도구 계약과 전문가 정책이 정하는 값이고, 이 서비스에는 그것을 해석할 권한이 없다 —
 * 숫자를 받아 두면 어느 화면에선가 비교하거나 등급을 매기게 된다.
 */
@Entity
@Table(name = "child_screening_record_domains")
public class ChildScreeningRecordDomain {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "screening_record_id", nullable = false)
  private ChildScreeningRecord screeningRecord;

  @Column(name = "domain_name", nullable = false, length = 60)
  private String domainName;

  @Column(name = "result_label", nullable = false, length = 120)
  private String resultLabel;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ChildScreeningRecordDomain() {}

  private ChildScreeningRecordDomain(
      ChildScreeningRecord screeningRecord,
      String domainName,
      String resultLabel,
      int displayOrder) {
    this.screeningRecord =
        Objects.requireNonNull(screeningRecord, "screeningRecord must not be null");
    this.domainName = Objects.requireNonNull(domainName, "domainName must not be null");
    this.resultLabel = Objects.requireNonNull(resultLabel, "resultLabel must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 영역별 라벨을 만든다.
   *
   * @param screeningRecord 소속 선별 결과 기록
   * @param domainName 영역 이름을 공식 결과지 그대로
   * @param resultLabel 영역 결과 라벨을 공식 결과지 그대로
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ChildScreeningRecordDomain create(
      ChildScreeningRecord screeningRecord,
      String domainName,
      String resultLabel,
      int displayOrder) {
    return new ChildScreeningRecordDomain(screeningRecord, domainName, resultLabel, displayOrder);
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
   * @return 영역 이름
   */
  public String getDomainName() {
    return domainName;
  }

  /**
   * @return 영역 결과 라벨
   */
  public String getResultLabel() {
    return resultLabel;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
