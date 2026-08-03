package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import jakarta.persistence.LockModeType;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 커뮤니티 첨부 이미지 Metadata의 연결·조회 저장소다. */
public interface CommunityAttachmentFileRepository
    extends JpaRepository<CommunityAttachmentFile, Long> {

  /** 파일 ID와 업로드 사용자 범위에서 연결할 Metadata를 잠금 조회한다. */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select f from CommunityAttachmentFile f "
          + "where f.fileId in :fileIds and f.uploadedByUserId = :userId")
  List<CommunityAttachmentFile> findOwnedFilesForUpdate(
      @Param("fileIds") Collection<String> fileIds, @Param("userId") Long userId);

  /** 게시글 첨부를 노출 순서대로 조회한다. */
  List<CommunityAttachmentFile> findAllByPostIdOrderByDisplayOrderAsc(Long postId);

  /** 수정·삭제 중인 게시글의 기존 첨부 목록을 잠금 조회한다. */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select f from CommunityAttachmentFile f where f.postId = :postId")
  List<CommunityAttachmentFile> findAllByPostIdForUpdate(@Param("postId") Long postId);

  /** 외부 파일 ID로 첨부 Metadata를 조회한다. */
  Optional<CommunityAttachmentFile> findByFileId(String fileId);
}
