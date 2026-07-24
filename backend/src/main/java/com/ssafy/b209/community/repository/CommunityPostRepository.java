package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.CommunityPost;
import org.springframework.data.jpa.repository.JpaRepository;

/** 커뮤니티 게시글 작성 등 쓰기 작업에 사용하는 표준 JPA 저장소다. */
public interface CommunityPostRepository extends JpaRepository<CommunityPost, Long> {}
