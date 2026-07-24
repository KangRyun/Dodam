package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.CommunityPost;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 커뮤니티 게시글 작성·수정·삭제 등 쓰기 작업에 사용하는 표준 JPA 저장소다. */
public interface CommunityPostRepository extends JpaRepository<CommunityPost, Long> {

  /**
   * 삭제되지 않은 게시글을 현재 Transaction의 쓰기 잠금으로 조회한다.
   *
   * <p>상태가 {@code DELETED}이거나 삭제 시각이 있는 게시글은 제외해 이미 삭제된 게시글의 재수정·재삭제를 없는 게시글과 동일하게 처리한다.
   *
   * @param id 게시글 식별자
   * @return 삭제되지 않은 게시글, 없거나 Soft Delete된 경우 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select p from CommunityPost p "
          + "where p.id = :id "
          + "and p.postStatus <> com.ssafy.b209.community.domain.PostStatus.DELETED "
          + "and p.deletedAt is null")
  Optional<CommunityPost> findNotDeletedByIdForUpdate(@Param("id") Long id);
}
