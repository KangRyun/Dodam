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

/** 리포트의 객관적 활동 주의사항을 노출 순서와 함께 저장한다. */
@Entity
@Table(name = "report_activity_notes")
public class ReportActivityNote {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "note_text", nullable = false, columnDefinition = "TEXT")
  private String noteText;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportActivityNote() {}

  private ReportActivityNote(Report report, String noteText, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.noteText = requireText(noteText, "noteText");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
  }

  /**
   * 리포트에 연결되는 활동 주의사항을 생성한다.
   *
   * @param report 주의사항이 속한 리포트
   * @param noteText 객관적 활동 주의사항 문구
   * @param displayOrder 0부터 시작하는 노출 순서
   * @return 저장 가능한 활동 주의사항
   * @throws IllegalArgumentException 문구가 비었거나 순서가 음수인 경우
   */
  public static ReportActivityNote create(Report report, String noteText, int displayOrder) {
    return new ReportActivityNote(report, noteText, displayOrder);
  }

  /**
   * @return 활동 주의사항 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 객관적 활동 주의사항 문구
   */
  public String getNoteText() {
    return noteText;
  }

  /**
   * @return 0부터 시작하는 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
