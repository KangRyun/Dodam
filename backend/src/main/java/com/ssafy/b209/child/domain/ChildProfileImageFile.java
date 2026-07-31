package com.ssafy.b209.child.domain;

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

/**
 * 아동 프로필에 연결하기 위해 사전 업로드된 이미지의 소유권과 Storage Metadata를 보관한다.
 *
 * <p>외부에는 {@code fileId}만 노출하고 내부 {@code storageKey}는 파일 연결 및 인증 조회 과정에서만 사용한다. 업로드 직후에는 {@link
 * ChildProfileImageFileStatus#TEMP}이며 후속 아동 등록·수정 Transaction에서 연결된다.
 */
@Entity
@Table(name = "child_profile_image_files")
public class ChildProfileImageFile {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(
      name = "file_id",
      nullable = false,
      unique = true,
      length = 36,
      columnDefinition = "CHAR(36)")
  private String fileId;

  @Column(name = "uploaded_by_user_id", nullable = false)
  private Long uploadedByUserId;

  @Column(name = "storage_key", nullable = false, length = 1000)
  private String storageKey;

  @Column(name = "content_type", nullable = false, length = 100)
  private String contentType;

  @Column(name = "file_size_bytes", nullable = false)
  private Long fileSizeBytes;

  @Column(name = "width_px", nullable = false)
  private Integer widthPx;

  @Column(name = "height_px", nullable = false)
  private Integer heightPx;

  @Column(name = "checksum_sha256", nullable = false, length = 64, columnDefinition = "CHAR(64)")
  private String checksumSha256;

  @Enumerated(EnumType.STRING)
  @Column(name = "status", nullable = false, length = 20)
  private ChildProfileImageFileStatus status;

  @Column(name = "child_id")
  private Long childId;

  @Column(name = "expires_at", nullable = false)
  private LocalDateTime expiresAt;

  @Column(name = "attached_at")
  private LocalDateTime attachedAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected ChildProfileImageFile() {}

  private ChildProfileImageFile(
      String fileId,
      Long uploadedByUserId,
      String storageKey,
      String contentType,
      long fileSizeBytes,
      Integer widthPx,
      Integer heightPx,
      String checksumSha256,
      LocalDateTime expiresAt,
      LocalDateTime createdAt) {
    this.fileId = Objects.requireNonNull(fileId);
    this.uploadedByUserId = Objects.requireNonNull(uploadedByUserId);
    this.storageKey = Objects.requireNonNull(storageKey);
    this.contentType = Objects.requireNonNull(contentType);
    this.fileSizeBytes = fileSizeBytes;
    this.widthPx = Objects.requireNonNull(widthPx);
    this.heightPx = Objects.requireNonNull(heightPx);
    this.checksumSha256 = Objects.requireNonNull(checksumSha256);
    this.status = ChildProfileImageFileStatus.TEMP;
    this.expiresAt = Objects.requireNonNull(expiresAt);
    this.createdAt = Objects.requireNonNull(createdAt);
  }

  /**
   * 아직 아동과 연결되지 않은 임시 프로필 이미지 Metadata를 생성한다.
   *
   * @param fileId API에서 사용하는 불투명 UUID 문자열
   * @param uploadedByUserId 파일을 업로드한 보호자 사용자 ID
   * @param storageKey ImageStorage 내부 객체 Key
   * @param contentType Signature로 검증된 MIME Type
   * @param fileSizeBytes 검증 후 저장된 파일 크기
   * @param widthPx 이미지 너비
   * @param heightPx 이미지 높이
   * @param checksumSha256 실제 이미지 Byte의 SHA-256
   * @param expiresAt 연결되지 않은 파일의 만료 시각
   * @param createdAt 업로드 시각
   * @return TEMP 상태의 프로필 이미지 파일
   */
  public static ChildProfileImageFile temporary(
      String fileId,
      Long uploadedByUserId,
      String storageKey,
      String contentType,
      long fileSizeBytes,
      Integer widthPx,
      Integer heightPx,
      String checksumSha256,
      LocalDateTime expiresAt,
      LocalDateTime createdAt) {
    return new ChildProfileImageFile(
        fileId,
        uploadedByUserId,
        storageKey,
        contentType,
        fileSizeBytes,
        widthPx,
        heightPx,
        checksumSha256,
        expiresAt,
        createdAt);
  }

  /**
   * 임시 업로드 파일을 아동 프로필에 연결한다.
   *
   * @param childId 이미지를 사용할 아동 ID
   * @param attachedAt 연결 시각
   * @throws IllegalStateException 임시 상태가 아니거나 유효 시간이 지난 경우
   */
  public void attachTo(long childId, LocalDateTime attachedAt) {
    if (status != ChildProfileImageFileStatus.TEMP || !expiresAt.isAfter(attachedAt)) {
      throw new IllegalStateException("연결할 수 없는 프로필 이미지 파일입니다.");
    }
    this.status = ChildProfileImageFileStatus.ATTACHED;
    this.childId = childId;
    this.attachedAt = Objects.requireNonNull(attachedAt);
  }

  public String getFileId() {
    return fileId;
  }

  public Long getId() {
    return id;
  }

  public Long getUploadedByUserId() {
    return uploadedByUserId;
  }

  public String getStorageKey() {
    return storageKey;
  }

  public String getContentType() {
    return contentType;
  }

  public Long getFileSizeBytes() {
    return fileSizeBytes;
  }

  public Integer getWidthPx() {
    return widthPx;
  }

  public Integer getHeightPx() {
    return heightPx;
  }

  public String getChecksumSha256() {
    return checksumSha256;
  }

  public ChildProfileImageFileStatus getStatus() {
    return status;
  }

  public Long getChildId() {
    return childId;
  }

  public LocalDateTime getExpiresAt() {
    return expiresAt;
  }

  public LocalDateTime getAttachedAt() {
    return attachedAt;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
