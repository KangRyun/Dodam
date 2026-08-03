package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.CommunityComment;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 댓글 쓰기 작업에 사용하는 JPA 저장소다. */
public interface CommunityCommentRepository extends JpaRepository<CommunityComment, Long> {

  /** 삭제되지 않은 댓글을 수정·삭제용 잠금으로 조회한다. */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select c from CommunityComment c where c.id = :id "
          + "and c.commentStatus <> com.ssafy.b209.community.domain.CommentStatus.DELETED "
          + "and c.deletedAt is null")
  Optional<CommunityComment> findNotDeletedByIdForUpdate(@Param("id") Long id);
}
