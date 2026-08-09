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
 * 리포트가 근거로 참조한 전문 자료 출처다 (875 §9, S15P11B209-614).
 *
 * <p><strong>출처 표시는 라이선스 의무(KOGL-1)</strong>이자 보호자 신뢰 재료다. AI 가 {@code ragReferences}로 보내 온 것을 그대로
 * 남긴다 — 표시하지 않으면 인용한 자료의 이용 조건을 어긴다.
 *
 * <p>{@code url}은 nullable 이다. AI 는 링크를 보내지 않고 자체 저작 자료는 애초에 URL 이 없다 — 875 §9 가 nullable 을 유지하기로 한
 * 이유가 이 경우다.
 */
@Entity
@Table(name = "report_references")
public class ReportReference {

  /** 제목 컬럼 길이다. */
  public static final int TITLE_MAX_LENGTH = 300;

  /** 출처 식별자 컬럼 길이다. */
  public static final int SOURCE_ID_MAX_LENGTH = 120;

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "source_id", length = SOURCE_ID_MAX_LENGTH)
  private String sourceId;

  @Column(name = "title", nullable = false, length = TITLE_MAX_LENGTH)
  private String title;

  @Column(name = "url", length = 500)
  private String url;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportReference() {}

  private ReportReference(
      Report report, int displayOrder, String sourceId, String title, String url) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.sourceId = sourceId;
    if (title == null || title.isBlank()) {
      throw new IllegalArgumentException("title must not be blank");
    }
    this.title = title;
    this.url = url;
  }

  /**
   * 리포트에 연결되는 참고 자료 한 건을 생성한다.
   *
   * @param report 자료가 속한 리포트
   * @param displayOrder 0부터 시작하는 노출 순서
   * @param sourceId 자료 출처 식별자이며 없으면 {@code null}
   * @param title 자료 제목
   * @param url 자료 링크이며 없으면 {@code null}
   * @return 저장 가능한 참고 자료
   * @throws IllegalArgumentException 순서가 음수이거나 제목이 빈 경우
   */
  public static ReportReference create(
      Report report, int displayOrder, String sourceId, String title, String url) {
    return new ReportReference(report, displayOrder, sourceId, title, url);
  }

  /**
   * @return 참고 자료 식별자
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
   * @return 자료 출처 식별자이며 없으면 {@code null}
   */
  public String getSourceId() {
    return sourceId;
  }

  /**
   * @return 자료 제목
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 자료 링크이며 없으면 {@code null}
   */
  public String getUrl() {
    return url;
  }
}
