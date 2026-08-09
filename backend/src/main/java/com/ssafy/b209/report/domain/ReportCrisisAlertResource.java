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

/** 위기 대응 안내에 함께 싣는 상담·신고 자원 한 건이다 (S15P11B209-902). */
@Entity
@Table(name = "report_crisis_alert_resources")
public class ReportCrisisAlertResource {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private ReportCrisisAlert crisisAlert;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "resource_name", nullable = false, length = 100)
  private String resourceName;

  @Column(name = "contact", nullable = false, length = 100)
  private String contact;

  @Column(name = "note", nullable = false, length = 300)
  private String note;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportCrisisAlertResource() {}

  private ReportCrisisAlertResource(
      ReportCrisisAlert crisisAlert,
      int displayOrder,
      String resourceName,
      String contact,
      String note) {
    this.crisisAlert = Objects.requireNonNull(crisisAlert, "crisisAlert must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.resourceName = requireText(resourceName, "resourceName");
    this.contact = requireText(contact, "contact");
    this.note = note == null ? "" : note;
  }

  /**
   * 상담·신고 자원을 생성한다.
   *
   * @param crisisAlert 자원이 속한 위기 안내
   * @param displayOrder 0부터 시작하는 순서
   * @param resourceName 자원 이름
   * @param contact 연락처
   * @param note 보충 설명이며 없으면 빈 문자열로 저장한다
   * @return 저장 가능한 자원
   */
  static ReportCrisisAlertResource create(
      ReportCrisisAlert crisisAlert,
      int displayOrder,
      String resourceName,
      String contact,
      String note) {
    return new ReportCrisisAlertResource(crisisAlert, displayOrder, resourceName, contact, note);
  }

  /**
   * @return 0부터 시작하는 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 자원 이름
   */
  public String getResourceName() {
    return resourceName;
  }

  /**
   * @return 연락처
   */
  public String getContact() {
    return contact;
  }

  /**
   * @return 보충 설명
   */
  public String getNote() {
    return note;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
