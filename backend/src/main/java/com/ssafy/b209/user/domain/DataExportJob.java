package com.ssafy.b209.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/** 인증 사용자가 요청한 비동기 데이터 내보내기 작업이다. */
@Entity
@Table(name = "data_export_jobs")
public class DataExportJob {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "user_id", nullable = false)
  private Long userId;

  @Enumerated(EnumType.STRING)
  @Column(name = "export_status", nullable = false, length = 20)
  private DataExportStatus exportStatus;

  @Column(name = "storage_key", length = 1000)
  private String storageKey;

  @Column(name = "expires_at")
  private LocalDateTime expiresAt;

  @Column(name = "completed_at")
  private LocalDateTime completedAt;

  @Column(name = "error_code", length = 80)
  private String errorCode;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  /** JPA가 Entity를 복원할 때 사용한다. */
  protected DataExportJob() {}

  private DataExportJob(Long userId, LocalDateTime requestedAt) {
    this.userId = Objects.requireNonNull(userId, "userId must not be null");
    this.exportStatus = DataExportStatus.PENDING;
    this.createdAt = Objects.requireNonNull(requestedAt, "requestedAt must not be null");
    this.updatedAt = requestedAt;
  }

  /**
   * ZIP 생성 전 대기 상태의 내보내기 작업을 만든다.
   *
   * @param userId 인증된 요청 사용자 식별자
   * @param requestedAt 작업 접수 시각
   * @return 아직 처리되지 않은 내보내기 작업
   */
  public static DataExportJob requested(Long userId, LocalDateTime requestedAt) {
    return new DataExportJob(userId, requestedAt);
  }

  /**
   * @return 영속화된 내보내기 작업 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 작업을 요청한 사용자 식별자
   */
  public Long getUserId() {
    return userId;
  }

  /**
   * @return 현재 내보내기 작업 상태
   */
  public DataExportStatus getExportStatus() {
    return exportStatus;
  }

  /**
   * @return 작업 접수 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * @return 내보내기 파일 다운로드 만료 시각
   */
  public LocalDateTime getExpiresAt() {
    return expiresAt;
  }

  /**
   * @return 내보내기 작업 완료 시각
   */
  public LocalDateTime getCompletedAt() {
    return completedAt;
  }

  /**
   * @return 작업 실패 시 기록한 안전한 오류 코드
   */
  public String getErrorCode() {
    return errorCode;
  }
}
