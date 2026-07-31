package com.ssafy.b209.child.repository;

import com.ssafy.b209.child.domain.ChildProfileImageFile;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

/** 아동 프로필 이미지의 공개 식별자·소유권·Storage Metadata를 관리한다. */
public interface ChildProfileImageFileRepository
    extends JpaRepository<ChildProfileImageFile, Long> {

  /**
   * 외부 API가 전달한 파일 식별자로 프로필 이미지 Metadata를 조회한다.
   *
   * @param fileId 업로드 API가 발급한 UUID 문자열
   * @return 식별자에 대응하는 파일
   */
  Optional<ChildProfileImageFile> findByFileId(String fileId);

  @Lock(LockModeType.PESSIMISTIC_WRITE)
  Optional<ChildProfileImageFile> findByFileIdAndUploadedByUserId(
      String fileId, Long uploadedByUserId);

  Optional<ChildProfileImageFile> findByChildId(Long childId);
}
