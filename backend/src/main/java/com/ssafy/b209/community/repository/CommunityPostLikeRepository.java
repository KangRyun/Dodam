package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.CommunityPostLike;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 커뮤니티 게시글 좋아요의 존재 확인, 집계, 생성·삭제를 담당하는 JPA 저장소다. */
public interface CommunityPostLikeRepository extends JpaRepository<CommunityPostLike, Long> {

  /** 게시글과 사용자가 같은 좋아요를 조회한다. */
  Optional<CommunityPostLike> findByPostIdAndUserId(Long postId, Long userId);

  /** 게시글에 남아 있는 전체 좋아요 수를 반환한다. */
  long countByPostId(Long postId);
}
