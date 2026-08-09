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
import java.util.Set;

/**
 * 리포트 '그린 것' 한 건이다 (S15P11B209-912).
 *
 * <p><strong>출처는 VLM 관찰 서술이며 YOLO 탐지 라벨이 아니다.</strong> 탐지 임계값(0.20)은 "박스를 남길지"의 기준이라 그 라벨을 보호자에게 확정
 * 사실로 적을 수 없다. AI 가 서술 원문과 대조해 걸러 보낸 값만 저장한다(S15P11B209-911).
 *
 * <p>{@code displayOrder}는 주제 순서(집→나무→사람)를 보존한다. 화면과 PDF 가 이 순서로 이어 붙여 한 문장을 만들기 때문에 순서가 계약이다.
 */
@Entity
@Table(name = "report_drawn_items")
public class ReportDrawnItem {

  /** 이름 컬럼 길이다. AI 계약은 20자 이내를 보내지만 초과분을 조용히 자르지 않기 위해 여유를 둔다. */
  public static final int NAME_MAX_LENGTH = 100;

  /** 보호자 화면에 표시하는 AI 계약상 이름 최대 문자 수다. */
  public static final int DISPLAY_NAME_MAX_CODE_POINTS = 20;

  private static final Set<String> ALLOWED_SUBJECTS = Set.of("HOUSE", "TREE", "PERSON");

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "drawing_subject", length = 10)
  private String drawingSubject;

  @Column(name = "name", nullable = false, length = NAME_MAX_LENGTH)
  private String name;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDrawnItem() {}

  private ReportDrawnItem(Report report, int displayOrder, String drawingSubject, String name) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.drawingSubject = normalizeSubject(drawingSubject);
    if (name == null || name.isBlank()) {
      throw new IllegalArgumentException("name must not be blank");
    }
    if (name.codePointCount(0, name.length()) > NAME_MAX_LENGTH) {
      throw new IllegalArgumentException("name must not exceed " + NAME_MAX_LENGTH + " characters");
    }
    this.name = name;
  }

  /**
   * 리포트에 연결되는 '그린 것' 한 건을 생성한다.
   *
   * @param report 항목이 속한 리포트
   * @param displayOrder 0부터 시작하는 노출 순서이며 주제 순서를 보존한다
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})이며 그림일기는 {@code null}
   * @param name 보호자 화면에 그대로 나가는 한국어 표현
   * @return 저장 가능한 '그린 것' 항목
   * @throws IllegalArgumentException 순서가 음수이거나 이름이 비었거나 허용하지 않는 주제인 경우
   */
  public static ReportDrawnItem create(
      Report report, int displayOrder, String drawingSubject, String name) {
    return new ReportDrawnItem(report, displayOrder, drawingSubject, name);
  }

  /**
   * @return '그린 것' 식별자
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
   * @return HTP 주제이며 그림일기는 {@code null}
   */
  public String getDrawingSubject() {
    return drawingSubject;
  }

  /**
   * @return 보호자 화면에 그대로 나가는 한국어 표현
   */
  public String getName() {
    return name;
  }

  /**
   * 주제 값을 정규화한다.
   *
   * <p>AI 가 보낸 값이 HTP 주제가 아니면 그림일기로 취급한다({@code null}). 알 수 없는 주제를 그대로 저장하면 DB CHECK 위반으로 리포트 저장
   * 전체가 실패하는데, '그린 것' 한 줄 때문에 리포트를 죽이는 것은 과하다.
   */
  private static String normalizeSubject(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    String normalized = value.trim().toUpperCase(java.util.Locale.ROOT);
    return ALLOWED_SUBJECTS.contains(normalized) ? normalized : null;
  }
}
