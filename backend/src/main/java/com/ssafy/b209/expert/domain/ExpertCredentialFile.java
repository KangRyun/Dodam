package com.ssafy.b209.expert.domain;

import com.ssafy.b209.storage.credential.StoredCredentialFile;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/** 전문가 자격과 보호된 Storage 객체의 연결 Metadata를 보관한다. */
@Entity
@Table(name = "expert_credential_files")
public class ExpertCredentialFile {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "expert_credential_id", nullable = false)
  private ExpertCredential expertCredential;

  @Column(name = "storage_key", nullable = false, length = 1000)
  private String storageKey;

  @Column(name = "storage_key_hash", nullable = false, length = 64, columnDefinition = "CHAR(64)")
  private String storageKeyHash;

  @Column(name = "file_name", length = 255)
  private String fileName;

  @Column(name = "mime_type", length = 100)
  private String mimeType;

  @Column(name = "file_size_bytes")
  private Long fileSizeBytes;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected ExpertCredentialFile() {}

  /**
   * 저장 완료된 파일을 첫 번째 자격 증빙으로 연결한다.
   *
   * @param credential 파일을 소유할 자격
   * @param stored 검증과 저장을 마친 파일 Metadata
   * @param originalFilename Client가 전달한 원본 파일명
   * @param now 연결 생성 시각
   * @return 자격에 연결할 파일 Entity
   */
  public static ExpertCredentialFile first(
      ExpertCredential credential,
      StoredCredentialFile stored,
      String originalFilename,
      LocalDateTime now) {
    ExpertCredentialFile file = new ExpertCredentialFile();
    file.expertCredential = Objects.requireNonNull(credential);
    file.storageKey = stored.storageKey();
    file.storageKeyHash = stored.storageKeyHash();
    file.fileName = normalizeFilename(originalFilename);
    file.mimeType = stored.contentType();
    file.fileSizeBytes = stored.size();
    file.displayOrder = 0;
    file.createdAt = Objects.requireNonNull(now);
    return file;
  }

  public String getFileName() {
    return fileName;
  }

  public String getMimeType() {
    return mimeType;
  }

  public Long getFileSizeBytes() {
    return fileSizeBytes;
  }

  /**
   * 내부 파일 삭제에 사용하는 Storage Key를 반환한다.
   *
   * <p>API 응답에는 노출하지 않고 Storage Adapter에만 전달해야 한다.
   *
   * @return Local 또는 S3 내부 Storage Key
   */
  public String getStorageKey() {
    return storageKey;
  }

  private static String normalizeFilename(String value) {
    if (value == null || value.isBlank()) return null;
    String normalized = value.replace('\\', '/');
    String name = normalized.substring(normalized.lastIndexOf('/') + 1).trim();
    return name.isEmpty() ? null : name.substring(0, Math.min(name.length(), 255));
  }
}
