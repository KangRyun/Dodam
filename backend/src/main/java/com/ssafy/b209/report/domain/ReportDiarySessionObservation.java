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
 * 그림일기 V2 에서 이번 활동에만 확인된 표현이다.
 *
 * <p>{@link ReportPublicInterpretation}(주요 심리 경향)을 대신하는 자리다. 한 번의 그림일기로 "성취욕이 강한 편이에요"처럼 지속적인 성향을
 * 말하면 근거가 부족한 진단이 된다 — 표현을 부드럽게 바꿔도 마찬가지다. 그래서 그림일기에서는 경향 카드를 서버가 전부 제외하고 이 자리만 쓴다.
 *
 * <p>{@code scopeText} 를 함께 저장하는 이유도 같다. 화면에서 "이번 활동에서 확인된 모습"이라는 범위가 카드에 붙어 있어야 보호자가 지속적인 특질로 읽지
 * 않는다.
 */
@Entity
@Table(name = "report_diary_session_observations")
public class ReportDiarySessionObservation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "observation_code", nullable = false, length = 60)
  private String observationCode;

  @Column(name = "title", nullable = false, length = 200)
  private String title;

  @Column(name = "description", nullable = false, columnDefinition = "TEXT")
  private String description;

  @Column(name = "scope_text", nullable = false, length = 200)
  private String scopeText;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiarySessionObservation() {}

  private ReportDiarySessionObservation(
      Report report,
      String observationCode,
      String title,
      String description,
      String scopeText,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.observationCode =
        Objects.requireNonNull(observationCode, "observationCode must not be null");
    this.title = Objects.requireNonNull(title, "title must not be null");
    this.description = Objects.requireNonNull(description, "description must not be null");
    this.scopeText = Objects.requireNonNull(scopeText, "scopeText must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 이번 활동 관찰을 만든다.
   *
   * @param report 소속 리포트
   * @param observationCode 관찰 코드
   * @param title 보호자에게 보이는 제목
   * @param description 근거에 묶인 이번 활동 한정 설명
   * @param scopeText 범위를 알리는 문구
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiarySessionObservation create(
      Report report,
      String observationCode,
      String title,
      String description,
      String scopeText,
      int displayOrder) {
    return new ReportDiarySessionObservation(
        report, observationCode, title, description, scopeText, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 관찰 코드
   */
  public String getObservationCode() {
    return observationCode;
  }

  /**
   * @return 보호자에게 보이는 제목
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 이번 활동 한정 설명
   */
  public String getDescription() {
    return description;
  }

  /**
   * @return 범위를 알리는 문구
   */
  public String getScopeText() {
    return scopeText;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
