package com.ssafy.b209.community.domain;

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

/** 커뮤니티 게시글에 연결할 이미지의 소유권과 검증된 Storage Metadata를 보관한다. */
@Entity
@Table(name = "community_attachment_files")
public class CommunityAttachmentFile {

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
  private CommunityAttachmentStatus status;

  @Column(name = "post_id")
  private Long postId;

  @Column(name = "display_order")
  private Integer displayOrder;

  @Column(name = "expires_at", nullable = false)
  private LocalDateTime expiresAt;

  @Column(name = "attached_at")
  private LocalDateTime attachedAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected CommunityAttachmentFile() {}

  private CommunityAttachmentFile(
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
    this.status = CommunityAttachmentStatus.TEMP;
    this.expiresAt = Objects.requireNonNull(expiresAt);
    this.createdAt = Objects.requireNonNull(createdAt);
  }

  /**
   * 게시글 연결 전 임시 첨부 파일 Metadata를 생성한다.
   *
   * @return 24시간 연결 대기 상태의 첨부 파일
   */
  public static CommunityAttachmentFile temporary(
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
    return new CommunityAttachmentFile(
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
   * 유효한 임시 파일을 게시글의 지정 순서에 연결한다.
   *
   * @param postId 연결할 게시글 ID
   * @param displayOrder 게시글 내 노출 순서
   * @param now 연결 시각
   * @throws IllegalStateException 임시 상태가 아니거나 만료된 경우
   */
  public void attachTo(long postId, int displayOrder, LocalDateTime now) {
    if (status != CommunityAttachmentStatus.TEMP || !expiresAt.isAfter(now)) {
      throw new IllegalStateException("연결할 수 없는 커뮤니티 첨부 파일입니다.");
    }
    this.status = CommunityAttachmentStatus.ATTACHED;
    this.postId = postId;
    this.displayOrder = displayOrder;
    this.attachedAt = now;
  }

  /**
   * 같은 게시글에 유지되는 첨부 이미지의 노출 순서를 변경한다.
   *
   * @param postId 현재 연결된 게시글 ID
   * @param displayOrder 새 노출 순서
   * @throws IllegalStateException 다른 게시글 파일이거나 연결 상태가 아닌 경우
   */
  public void reorder(long postId, int displayOrder) {
    if (status != CommunityAttachmentStatus.ATTACHED || !Objects.equals(this.postId, postId)) {
      throw new IllegalStateException("다른 게시글의 첨부 순서를 변경할 수 없습니다.");
    }
    this.displayOrder = displayOrder;
  }

  public Long getId() {
    return id;
  }

  public String getFileId() {
    return fileId;
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

  public CommunityAttachmentStatus getStatus() {
    return status;
  }

  public Long getPostId() {
    return postId;
  }

  public Integer getDisplayOrder() {
    return displayOrder;
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
