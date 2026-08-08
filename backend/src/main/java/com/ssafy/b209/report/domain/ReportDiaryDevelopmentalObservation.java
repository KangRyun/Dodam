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
 * 그림일기 연령 발달 맥락 관찰 한 건이다.
 *
 * <p>세 조각이 한 행에 함께 있는 것이 이 표의 요점이다 — <strong>연령 맥락 → 이번 활동 관찰 → 범위 고지.</strong> 맥락만 보여 주면 규준 설명이
 * 되고, 관찰만 보여 주면 무슨 뜻인지 알 수 없으며, 범위 고지가 빠지면 한 회차가 발달 평가로 읽힌다.
 *
 * <p>{@code status} 가 {@code NOT_ASSESSED} 면 "확인하지 않았다"는 뜻이지 "못한다"가 아니다. 아이의 무응답·건너뜀·짧은 답은 발달 결함이
 * 아니다.
 *
 * <p>연령 맥락 문장은 검수된 공개 자료에서만 온다. 어떤 문장이 붙을지는 AI 서버가 등록부와 나이로 정하며 <strong>LLM 이 일반 지식으로 보충하지
 * 않는다</strong> — 맡기면 "또래보다 빠르다"가 곧바로 나온다.
 */
@Entity
@Table(name = "report_diary_developmental_observations")
public class ReportDiaryDevelopmentalObservation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "domain", nullable = false, length = 30)
  private String domain;

  @Column(name = "status", nullable = false, length = 30)
  private String status;

  @Column(name = "age_context", nullable = false, columnDefinition = "TEXT")
  private String ageContext;

  @Column(name = "observation", nullable = false, columnDefinition = "TEXT")
  private String observation;

  @Column(name = "scope_text", nullable = false, length = 200)
  private String scopeText;

  /**
   * 이 맥락이 무엇을 주장하는지 (S15P11B209-1010 v2).
   *
   * <p>문구가 아니라 값으로 구분한다 — 문구로만 나누면 문구를 다듬는 순간 구분이 사라진다.
   * 화면은 이 값으로 "연령 이정표"와 "학령 초기 참고 맥락"과 "이번 활동만"을 가른다.
   */
  @Column(name = "context_type", nullable = false, length = 40)
  private String contextType;

  /** 보호자가 활동에 이어 그대로 물어볼 수 있는 질문이며 없으면 {@code null}. */
  @Column(name = "caregiver_question", columnDefinition = "TEXT")
  private String caregiverQuestion;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryDevelopmentalObservation() {}

  private ReportDiaryDevelopmentalObservation(
      Report report,
      String domain,
      String status,
      String ageContext,
      String observation,
      String scopeText,
      String contextType,
      String caregiverQuestion,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.domain = Objects.requireNonNull(domain, "domain must not be null");
    this.status = Objects.requireNonNull(status, "status must not be null");
    this.ageContext = Objects.requireNonNull(ageContext, "ageContext must not be null");
    this.observation = Objects.requireNonNull(observation, "observation must not be null");
    this.scopeText = Objects.requireNonNull(scopeText, "scopeText must not be null");
    this.contextType = Objects.requireNonNull(contextType, "contextType must not be null");
    this.caregiverQuestion = caregiverQuestion;
    this.displayOrder = displayOrder;
  }

  /**
   * 발달 맥락 관찰을 만든다.
   *
   * @param report 소속 리포트
   * @param domain 관찰 도메인
   * @param status 관찰 상태
   * @param ageContext 검수 출처에서 온 연령 맥락 한 줄
   * @param observation 이번 활동에서 확인된 표현
   * @param scopeText 범위 고지이며 화면에 항상 함께 나간다
   * @param contextType 맥락이 무엇을 주장하는지
   * @param caregiverQuestion 보호자가 이어서 물어볼 질문이며 없으면 {@code null}
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryDevelopmentalObservation create(
      Report report,
      String domain,
      String status,
      String ageContext,
      String observation,
      String scopeText,
      String contextType,
      String caregiverQuestion,
      int displayOrder) {
    return new ReportDiaryDevelopmentalObservation(
        report,
        domain,
        status,
        ageContext,
        observation,
        scopeText,
        contextType,
        caregiverQuestion,
        displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 관찰 도메인
   */
  public String getDomain() {
    return domain;
  }

  /**
   * @return 관찰 상태
   */
  public String getStatus() {
    return status;
  }

  /**
   * @return 연령 맥락 한 줄
   */
  public String getAgeContext() {
    return ageContext;
  }

  /**
   * @return 이번 활동에서 확인된 표현
   */
  public String getObservation() {
    return observation;
  }

  /**
   * @return 범위 고지
   */
  public String getScopeText() {
    return scopeText;
  }

  /**
   * @return 이 맥락이 무엇을 주장하는지
   */
  public String getContextType() {
    return contextType;
  }

  /**
   * @return 보호자가 이어서 물어볼 질문이며 없으면 {@code null}
   */
  public String getCaregiverQuestion() {
    return caregiverQuestion;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
