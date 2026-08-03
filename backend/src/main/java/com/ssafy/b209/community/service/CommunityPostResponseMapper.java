package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.dto.CommunityAttachmentResponse;
import com.ssafy.b209.community.dto.PostDetailAuthorResponse;
import com.ssafy.b209.community.dto.PostDetailResponse;
import java.time.ZoneOffset;
import java.util.List;

/**
 * 쓰기 작업(작성·수정) 직후 게시글을 상세 조회와 동일한 형태의 응답으로 변환한다.
 *
 * <p>작성과 수정이 같은 매핑 규칙을 공유하도록 한곳에서 관리한다. 좋아요·댓글 집계와 좋아요 여부는 이 쓰기 경로의 범위 밖이므로 각각 0과 {@code false}로
 * 두며, 완전한 값은 상세 조회 API가 제공한다. 요청자는 항상 작성자 본인이므로 수정 가능 여부는 {@code true}다. 익명 게시글은 작성자 공개 정보를 노출하지
 * 않는다.
 */
final class CommunityPostResponseMapper {

  private CommunityPostResponseMapper() {}

  /**
   * 저장·수정된 게시글을 상세 응답으로 변환한다.
   *
   * @param post 저장·수정된 게시글 Entity
   * @param author 게시글 작성자 사용자
   * @return 쓰기 직후 상세 응답
   */
  static PostDetailResponse toDetailResponse(
      CommunityPost post, User author, List<CommunityAttachmentResponse> attachments) {
    PostDetailAuthorResponse authorResponse =
        post.isAnonymous()
            ? null
            : new PostDetailAuthorResponse(author.getId(), author.getNickname(), null);
    return new PostDetailResponse(
        post.getId(),
        post.getPostType(),
        post.getTitle(),
        post.getContent(),
        authorResponse,
        post.isAnonymous(),
        List.copyOf(attachments),
        List.of(),
        0L,
        0L,
        false,
        true,
        post.getCreatedAt().toInstant(ZoneOffset.UTC),
        post.getUpdatedAt().toInstant(ZoneOffset.UTC));
  }
}
