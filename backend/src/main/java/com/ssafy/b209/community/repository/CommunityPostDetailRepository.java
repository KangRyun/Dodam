package com.ssafy.b209.community.repository;

import java.util.List;
import java.util.Optional;

/**
 * DB v1.2의 게시글·작성자·좋아요·댓글·Template 관계에서 공개 상세 정보를 조회한다.
 *
 * <p>게시글 본문 조회와 Template 항목 조회를 분리해 집계 때문에 Template 행이 중복되는 것을 방지한다.
 */
public interface CommunityPostDetailRepository {

  /**
   * ACTIVE·공개·미삭제 조건을 만족하는 게시글 상세를 현재 사용자 집계와 함께 조회한다.
   *
   * @param postId 조회할 게시글 식별자
   * @param viewerUserId likedByMe와 editableByMe를 계산할 인증 사용자 ID
   * @return 일반 공개 가능한 게시글이면 상세 행, 없거나 비공개 상태면 빈 값
   */
  Optional<CommunityPostDetailRow> findPublicPost(Long postId, Long viewerUserId);

  /**
   * 게시글의 Template 항목을 DB display_order 오름차순으로 조회한다.
   *
   * @param postId 공개 확인을 마친 게시글 식별자
   * @return value_text 원문을 포함한 정렬된 Template 항목 목록
   */
  List<CommunityPostTemplateFieldRow> findTemplateFieldsByPostId(Long postId);
}
