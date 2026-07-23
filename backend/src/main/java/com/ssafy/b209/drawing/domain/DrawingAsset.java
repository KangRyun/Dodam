package com.ssafy.b209.drawing.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 그림 활동 세션에서 생성된 이미지 파일의 저장 위치와 검증 Metadata를 관리한다.
 *
 * <p>이미지 Byte 자체는 {@code ImageStorage} 구현체가 관리하며, 이 Entity에는 외부에 노출하지 않는 Storage Key와 파일 무결성 정보를
 * 기록한다.
 */
@Entity
@Table(name = "drawing_assets")
public class DrawingAsset {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @Enumerated(EnumType.STRING)
  @Column(name = "asset_type", nullable = false, length = 20)
  private DrawingAssetType assetType;

  @Column(name = "asset_version", nullable = false)
  private int assetVersion;

  @Column(name = "storage_key", nullable = false, length = 1000)
  private String storageKey;

  @Column(name = "file_url", length = 1000)
  private String fileUrl;

  @Column(name = "mime_type", nullable = false, length = 100)
  private String mimeType;

  @Column(name = "file_size_bytes", nullable = false)
  private long fileSizeBytes;

  @Column(name = "width_px")
  private Integer widthPx;

  @Column(name = "height_px")
  private Integer heightPx;

  @Column(name = "checksum_sha256", nullable = false, columnDefinition = "CHAR(64)")
  private String checksumSha256;

  @Column(name = "last_event_sequence")
  private Long lastEventSequence;

  @Column(name = "object_code", length = 100)
  private String objectCode;

  @Column(name = "captured_at", nullable = false)
  private LocalDateTime capturedAt;

  @Column(name = "expires_at")
  private LocalDateTime expiresAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected DrawingAsset() {}

  private DrawingAsset(
      DrawingSession drawingSession,
      DrawingAssetType assetType,
      int assetVersion,
      String storageKey,
      String mimeType,
      long fileSizeBytes,
      String checksumSha256,
      LocalDateTime capturedAt,
      LocalDateTime createdAt) {
    this.drawingSession = drawingSession;
    this.assetType = assetType;
    this.assetVersion = assetVersion;
    this.storageKey = storageKey;
    this.fileUrl = null;
    this.mimeType = mimeType;
    this.fileSizeBytes = fileSizeBytes;
    this.widthPx = null;
    this.heightPx = null;
    this.checksumSha256 = checksumSha256;
    this.lastEventSequence = null;
    this.objectCode = null;
    this.capturedAt = capturedAt;
    this.expiresAt = null;
    this.createdAt = createdAt;
  }

  /**
   * 검증과 저장을 마친 중간 또는 최종 그림 스냅샷의 Metadata를 생성한다.
   *
   * @param drawingSession 스냅샷이 속한 그림 활동 세션
   * @param assetType {@link DrawingAssetType#INTERMEDIATE} 또는 {@link DrawingAssetType#FINAL}
   * @param assetVersion 세션과 유형 안에서 증가하는 양의 버전
   * @param storageKey 이미지 저장소 내부 상대 Key
   * @param mimeType 실제 파일 Signature로 검증된 MIME Type
   * @param fileSizeBytes 실제 저장된 파일 크기(Byte)
   * @param checksumSha256 실제 저장된 Byte의 SHA-256 Hex
   * @param capturedAt 클라이언트가 스냅샷을 캡처한 UTC 시각
   * @param createdAt 서버가 Metadata를 생성한 UTC 시각
   * @return 영속화 전 그림 파일 Metadata
   * @throws IllegalArgumentException 지원하지 않는 유형 또는 유효하지 않은 버전인 경우
   */
  public static DrawingAsset snapshot(
      DrawingSession drawingSession,
      DrawingAssetType assetType,
      int assetVersion,
      String storageKey,
      String mimeType,
      long fileSizeBytes,
      String checksumSha256,
      LocalDateTime capturedAt,
      LocalDateTime createdAt) {
    Objects.requireNonNull(drawingSession, "drawingSession must not be null");
    Objects.requireNonNull(assetType, "assetType must not be null");
    if (!assetType.isSnapshotUploadType()) {
      throw new IllegalArgumentException("assetType must be INTERMEDIATE or FINAL");
    }
    if (assetVersion <= 0) {
      throw new IllegalArgumentException("assetVersion must be positive");
    }
    return new DrawingAsset(
        drawingSession,
        assetType,
        assetVersion,
        Objects.requireNonNull(storageKey, "storageKey must not be null"),
        Objects.requireNonNull(mimeType, "mimeType must not be null"),
        fileSizeBytes,
        Objects.requireNonNull(checksumSha256, "checksumSha256 must not be null"),
        Objects.requireNonNull(capturedAt, "capturedAt must not be null"),
        Objects.requireNonNull(createdAt, "createdAt must not be null"));
  }

  /**
   * 자동 저장된 현재 캔버스의 미리보기 Metadata를 생성한다.
   *
   * <p>초안은 최종·분석용 스냅샷과 구분되는 {@link DrawingAssetType#DRAFT}로 저장하며, 마지막 그림 이벤트 순서를 함께 기록해 늦게 도착한 이전
   * 초안을 판별할 수 있게 한다.
   *
   * @param drawingSession 초안이 속한 그림 활동 세션
   * @param assetVersion 세션의 초안 저장 순서에 따라 서버가 부여한 양의 버전
   * @param storageKey 이미지 저장소 내부 상대 Key
   * @param mimeType 실제 파일 Signature로 검증된 MIME Type
   * @param fileSizeBytes 실제 저장된 파일 크기(Byte)
   * @param checksumSha256 실제 저장된 Byte의 SHA-256 Hex
   * @param lastEventSequence 초안에 반영된 마지막 그림 이벤트 순서
   * @param capturedAt 클라이언트가 초안을 저장한 UTC 시각
   * @param createdAt 서버가 Metadata를 생성한 UTC 시각
   * @return 영속화 전 초안 Metadata
   * @throws IllegalArgumentException 버전이나 마지막 이벤트 순서가 양수가 아닌 경우
   */
  public static DrawingAsset draft(
      DrawingSession drawingSession,
      int assetVersion,
      String storageKey,
      String mimeType,
      long fileSizeBytes,
      String checksumSha256,
      long lastEventSequence,
      LocalDateTime capturedAt,
      LocalDateTime createdAt) {
    if (assetVersion <= 0) {
      throw new IllegalArgumentException("assetVersion must be positive");
    }
    if (lastEventSequence <= 0) {
      throw new IllegalArgumentException("lastEventSequence must be positive");
    }
    DrawingAsset asset =
        new DrawingAsset(
            Objects.requireNonNull(drawingSession, "drawingSession must not be null"),
            DrawingAssetType.DRAFT,
            assetVersion,
            Objects.requireNonNull(storageKey, "storageKey must not be null"),
            Objects.requireNonNull(mimeType, "mimeType must not be null"),
            fileSizeBytes,
            Objects.requireNonNull(checksumSha256, "checksumSha256 must not be null"),
            Objects.requireNonNull(capturedAt, "capturedAt must not be null"),
            Objects.requireNonNull(createdAt, "createdAt must not be null"));
    asset.lastEventSequence = lastEventSequence;
    return asset;
  }

  /**
   * 영속화된 그림 파일의 식별자를 제공한다.
   *
   * @return 그림 파일 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 파일의 생명주기와 접근 범위를 결정하는 소속 세션을 제공한다.
   *
   * @return 그림 파일이 속한 그림 활동 세션
   */
  public DrawingSession getDrawingSession() {
    return drawingSession;
  }

  /**
   * 중간·최종 그림 등 파일의 업무상 용도를 제공한다.
   *
   * @return 그림 파일 용도
   */
  public DrawingAssetType getAssetType() {
    return assetType;
  }

  /**
   * 같은 세션과 파일 유형 내 중복 판정에 사용하는 버전을 제공한다.
   *
   * @return 세션과 파일 유형 안에서의 버전
   */
  public int getAssetVersion() {
    return assetVersion;
  }

  /**
   * 파일 조회와 보상 삭제에 사용하는 저장소 내부 Key를 제공한다.
   *
   * @return 이미지 저장소 내부 상대 Key
   */
  public String getStorageKey() {
    return storageKey;
  }

  /**
   * 목록·미리보기에 사용할 수 있는 공개 파일 URL을 제공한다.
   *
   * <p>내부 저장 Key와 달리 외부에 노출해도 되는 값이며, 아직 공개 URL을 부여하지 않은 파일이면 {@code null}이다.
   *
   * @return 공개 파일 URL, 부여되지 않았으면 {@code null}
   */
  public String getFileUrl() {
    return fileUrl;
  }

  /**
   * 요청 Header가 아닌 파일 내용으로 확정한 형식을 제공한다.
   *
   * @return 실제 파일 Signature로 검증된 MIME Type
   */
  public String getMimeType() {
    return mimeType;
  }

  /**
   * 선언값이 아닌 저장 과정에서 측정한 파일 크기를 제공한다.
   *
   * @return 실제 저장된 파일 크기(Byte)
   */
  public long getFileSizeBytes() {
    return fileSizeBytes;
  }

  /**
   * 저장 파일의 무결성 확인에 사용하는 Checksum을 제공한다.
   *
   * @return 실제 저장된 Byte의 SHA-256 Hex
   */
  public String getChecksumSha256() {
    return checksumSha256;
  }

  /**
   * 초안에 반영된 마지막 그림 이벤트 순서를 제공한다.
   *
   * @return 초안이 아니거나 이벤트 순서를 기록하지 않은 파일이면 {@code null}
   */
  public Long getLastEventSequence() {
    return lastEventSequence;
  }

  /**
   * 업로드 시각과 구분되는 클라이언트 관측 시각을 제공한다.
   *
   * @return 클라이언트가 스냅샷을 캡처한 UTC 시각
   */
  public LocalDateTime getCapturedAt() {
    return capturedAt;
  }

  /**
   * 서버가 파일 저장을 완료하고 Metadata를 생성한 시각을 제공한다.
   *
   * @return 서버가 Metadata를 생성한 UTC 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
