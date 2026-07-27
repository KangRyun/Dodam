package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code drawing_assets} 한 행을 읽는 읽기 모델이다.
 *
 * <p>최종 이미지·썸네일의 공개 URL만 읽으며, 절대 경로나 저장 Key는 응답에 노출하지 않는다.
 */
@Entity
@Table(name = "drawing_assets")
public class ReportDrawingAssetView {

  @Id private Long id;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  @Column(name = "asset_type", nullable = false)
  private String assetType;

  @Column(name = "asset_version", nullable = false)
  private int assetVersion;

  @Column(name = "file_url")
  private String fileUrl;

  protected ReportDrawingAssetView() {}

  /**
   * @return 그림 파일 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 그림 활동 세션 식별자
   */
  public Long getDrawingSessionId() {
    return drawingSessionId;
  }

  /**
   * @return 파일 유형 코드
   */
  public String getAssetType() {
    return assetType;
  }

  /**
   * @return 파일 버전
   */
  public int getAssetVersion() {
    return assetVersion;
  }

  /**
   * @return 공개 파일 URL이며 없으면 {@code null}
   */
  public String getFileUrl() {
    return fileUrl;
  }
}
