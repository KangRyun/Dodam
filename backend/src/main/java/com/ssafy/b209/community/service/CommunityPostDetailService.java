package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.dto.PostDetailAuthorResponse;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.dto.PostTemplateDataResponse;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.community.repository.CommunityPostDetailRepository;
import com.ssafy.b209.community.repository.CommunityPostDetailRow;
import com.ssafy.b209.community.repository.CommunityPostTemplateFieldRow;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 사용자가 일반 공개 가능한 커뮤니티 게시글 상세를 조회하도록 조율한다.
 *
 * <p>상세 조회에는 역할별 추가 제한을 두지 않으며, 게시글 공개 조건이 맞지 않으면 존재 여부와 관계없이 동일한 404를 반환한다.
 */
@Service
@Transactional(readOnly = true)
public class CommunityPostDetailService {

  private static final List<Object> NO_ATTACHMENTS = List.of();

  private final CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver;
  private final CommunityPostDetailRepository communityPostDetailRepository;

  /**
   * 인증 사용자 확인과 상세 조회에 필요한 협력 객체를 주입한다.
   *
   * @param currentAuthenticatedUserResolver 검증된 Access JWT 사용자 ID 확인 도구
   * @param communityPostDetailRepository 공개 상세와 Template field 조회 저장소
   */
  public CommunityPostDetailService(
      CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver,
      CommunityPostDetailRepository communityPostDetailRepository) {
    this.currentAuthenticatedUserResolver = currentAuthenticatedUserResolver;
    this.communityPostDetailRepository = communityPostDetailRepository;
  }

  /**
   * 일반 공개 조건을 만족하는 게시글을 상세 응답으로 변환한다.
   *
   * <p>첨부 파일 저장 구조는 DB v1.2에 없으므로 {@code attachments}는 항상 빈 배열이다. Template의 {@code value_text}는
   * 숫자·불리언으로 복원하지 않고 문자열 원문 그대로 반환한다.
   *
   * @param postId 조회할 게시글 식별자
   * @return 공통 성공 응답으로 감쌀 공개 게시글 상세
   * @throws BusinessException 인증 사용자가 없거나 게시글이 없거나 일반 공개 조건을 만족하지 않는 경우
   */
  public PostDetailResponse getPost(Long postId) {
    Long viewerUserId = currentAuthenticatedUserResolver.requireUserId();
    CommunityPostDetailRow post =
        communityPostDetailRepository
            .findPublicPost(postId, viewerUserId)
            .orElseThrow(() -> new BusinessException(CommunityPostDetailErrorCode.POST_NOT_FOUND));
    List<PostTemplateDataResponse> templateData =
        communityPostDetailRepository.findTemplateFieldsByPostId(postId).stream()
            .map(this::toTemplateData)
            .toList();
    return toResponse(post, templateData);
  }

  /**
   * 공개 상세 Native Query 행과 정렬된 Template 데이터를 외부 DTO로 변환한다.
   *
   * @param post 공개 조건을 만족한 게시글 Snapshot
   * @param templateData DB display_order 순서를 유지하는 Template 응답 목록
   * @return 내부 DB 식별자와 저장 경로를 포함하지 않는 외부 상세 DTO
   */
  public PostDetailResponse toResponse(
      CommunityPostDetailRow post, List<PostTemplateDataResponse> templateData) {
    return new PostDetailResponse(
        post.postId(),
        post.postType(),
        post.title(),
        post.content(),
        toAuthor(post),
        post.anonymous(),
        NO_ATTACHMENTS,
        templateData,
        post.likeCount(),
        post.commentCount(),
        post.likedByMe(),
        post.editableByMe(),
        post.createdAt().toInstant(ZoneOffset.UTC),
        post.updatedAt().toInstant(ZoneOffset.UTC));
  }

  private PostDetailAuthorResponse toAuthor(CommunityPostDetailRow post) {
    if (post.anonymous() || post.authorId() == null) {
      return null;
    }
    return new PostDetailAuthorResponse(post.authorId(), post.nickname(), post.profileImageUrl());
  }

  private PostTemplateDataResponse toTemplateData(CommunityPostTemplateFieldRow field) {
    return new PostTemplateDataResponse(
        field.fieldCode(), field.valueType(), field.valueText(), field.displayOrder());
  }
}
