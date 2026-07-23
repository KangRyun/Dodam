package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.PostFeed;
import com.ssafy.b209.community.domain.PostListSort;
import com.ssafy.b209.community.domain.PostListSort.SortDirection;
import com.ssafy.b209.community.domain.PostListSort.SortField;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.dto.PostAuthorResponse;
import com.ssafy.b209.community.dto.PostListItemResponse;
import com.ssafy.b209.community.dto.PostListPageResponse;
import com.ssafy.b209.community.dto.PostListQuery;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.repository.CommunityPostListPage;
import com.ssafy.b209.community.repository.CommunityPostListRepository;
import com.ssafy.b209.community.repository.CommunityPostListRow;
import com.ssafy.b209.community.repository.PostListSearchCriteria;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 사용자를 기준으로 공개 커뮤니티 게시글 목록의 Query 검증, 권한 범위 및 응답 마스킹을 조율한다.
 *
 * <p>목록에는 ACTIVE·공개·미삭제 게시글만 포함하며 익명 게시글의 원 작성자 식별자는 Repository 결과에 있더라도 외부 DTO로 전달하지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class CommunityPostListService {

  private static final int DEFAULT_PAGE = 0;
  private static final int DEFAULT_SIZE = 20;
  private static final int MAX_SIZE = 100;
  private static final int MAX_KEYWORD_CODE_POINTS = 100;
  private static final int CONTENT_PREVIEW_CODE_POINTS = 200;

  private final CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver;
  private final UserRepository userRepository;
  private final CommunityPostListRepository communityPostListRepository;

  /**
   * 목록 권한 확인과 DB 조회에 필요한 협력 객체를 주입한다.
   *
   * @param currentAuthenticatedUserResolver 검증된 Access JWT 사용자 확인 도구
   * @param userRepository 인증 사용자 역할 확인 저장소
   * @param communityPostListRepository 공개 게시글 집계 조회 저장소
   */
  public CommunityPostListService(
      CurrentAuthenticatedUserResolver currentAuthenticatedUserResolver,
      UserRepository userRepository,
      CommunityPostListRepository communityPostListRepository) {
    this.currentAuthenticatedUserResolver = currentAuthenticatedUserResolver;
    this.userRepository = userRepository;
    this.communityPostListRepository = communityPostListRepository;
  }

  /**
   * 최신 COMM-01 계약에 맞게 목록 Query를 검증하고 공개 게시글 페이지를 반환한다.
   *
   * <p>목록 결과가 비어도 오류가 아니라 HTTP 200의 빈 페이지가 된다.
   *
   * @param query Controller가 전달한 원시 Query Parameter
   * @return 공통 응답으로 감쌀 게시글 목록 페이지
   * @throws BusinessException 인증 사용자가 없거나, 역할이 없거나, Query가 계약을 위반한 경우
   */
  public PostListPageResponse getPosts(PostListQuery query) {
    Long viewerUserId = currentAuthenticatedUserResolver.requireUserId();
    User viewer =
        userRepository
            .findById(viewerUserId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    if (viewer.getRole() == null) {
      throw new BusinessException(AuthErrorCode.ACCESS_DENIED);
    }

    PostListSearchCriteria criteria = toCriteria(query, viewerUserId);
    CommunityPostListPage result = communityPostListRepository.findPosts(criteria);
    List<PostListItemResponse> content = result.content().stream().map(this::toResponse).toList();
    int totalPages = totalPages(result.totalElements(), criteria.size());
    boolean first = criteria.page() == 0;
    boolean hasNext = criteria.page() + 1 < totalPages;
    boolean last = !hasNext;
    return new PostListPageResponse(
        content,
        criteria.page(),
        criteria.size(),
        result.totalElements(),
        totalPages,
        first,
        last,
        hasNext);
  }

  /**
   * 공개 Query Parameter를 Repository 전용 검색 조건으로 변환한다.
   *
   * @param query 원시 Query Parameter
   * @param viewerUserId 현재 인증 사용자 ID
   * @return enum, 페이지 범위와 정렬을 검증한 검색 조건
   * @throws BusinessException 허용하지 않는 enum·정렬·페이지가 전달된 경우
   */
  public PostListSearchCriteria toCriteria(PostListQuery query, Long viewerUserId) {
    int page = parsePage(query.page());
    int size = parseSize(query.size());
    if (page > Integer.MAX_VALUE / size) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
    return new PostListSearchCriteria(
        parseOptionalEnum(query.type(), PostType.class),
        parseKeywordPattern(query.keyword()),
        query.feed() == null ? PostFeed.ALL : parseRequiredEnum(query.feed(), PostFeed.class),
        parseAuthorRole(query.authorRole()),
        page,
        size,
        parseSort(query.sort()),
        viewerUserId);
  }

  private String parseKeywordPattern(String rawKeyword) {
    if (rawKeyword == null || rawKeyword.isBlank()) {
      return null;
    }
    String keyword = rawKeyword.trim();
    if (keyword.codePointCount(0, keyword.length()) > MAX_KEYWORD_CODE_POINTS) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
    return "%" + keyword.replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%";
  }

  private UserRole parseAuthorRole(String rawAuthorRole) {
    if (rawAuthorRole == null) {
      return null;
    }
    UserRole role = parseRequiredEnum(rawAuthorRole, UserRole.class);
    if (role != UserRole.GUARDIAN && role != UserRole.EXPERT) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
    return role;
  }

  private PostListItemResponse toResponse(CommunityPostListRow row) {
    return new PostListItemResponse(
        row.postId(),
        row.postType(),
        row.title(),
        contentPreview(row.content()),
        toAuthor(row),
        row.anonymous(),
        row.likeCount(),
        row.commentCount(),
        row.likedByMe(),
        row.createdAt().toInstant(ZoneOffset.UTC),
        row.updatedAt().toInstant(ZoneOffset.UTC));
  }

  private PostAuthorResponse toAuthor(CommunityPostListRow row) {
    if (row.anonymous()) {
      return null;
    }
    if (row.authorId() == null) {
      return null;
    }
    return new PostAuthorResponse(row.authorId(), row.nickname());
  }

  private String contentPreview(String content) {
    if (content == null
        || content.codePointCount(0, content.length()) <= CONTENT_PREVIEW_CODE_POINTS) {
      return content;
    }
    int endIndex = content.offsetByCodePoints(0, CONTENT_PREVIEW_CODE_POINTS);
    return content.substring(0, endIndex) + "…";
  }

  private int totalPages(long totalElements, int size) {
    long pages = (totalElements + size - 1) / size;
    return pages > Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) pages;
  }

  private int parsePage(String rawPage) {
    if (rawPage == null) {
      return DEFAULT_PAGE;
    }
    try {
      int page = Integer.parseInt(rawPage);
      if (page < 0) {
        throw new NumberFormatException("page must be non-negative");
      }
      return page;
    } catch (NumberFormatException exception) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
  }

  private int parseSize(String rawSize) {
    if (rawSize == null) {
      return DEFAULT_SIZE;
    }
    try {
      int size = Integer.parseInt(rawSize);
      if (size < 1 || size > MAX_SIZE) {
        throw new NumberFormatException("size out of range");
      }
      return size;
    } catch (NumberFormatException exception) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
  }

  private PostListSort parseSort(String rawSort) {
    if (rawSort == null) {
      return new PostListSort(SortField.CREATED_AT, SortDirection.DESC);
    }
    String[] tokens = rawSort.split(",", -1);
    if (tokens.length != 2) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
    SortField field =
        switch (tokens[0]) {
          case "createdAt" -> SortField.CREATED_AT;
          case "likeCount" -> SortField.LIKE_COUNT;
          default -> throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
        };
    SortDirection direction =
        switch (tokens[1]) {
          case "asc" -> SortDirection.ASC;
          case "desc" -> SortDirection.DESC;
          default -> throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
        };
    return new PostListSort(field, direction);
  }

  private <T extends Enum<T>> T parseOptionalEnum(String rawValue, Class<T> enumType) {
    return rawValue == null ? null : parseRequiredEnum(rawValue, enumType);
  }

  private <T extends Enum<T>> T parseRequiredEnum(String rawValue, Class<T> enumType) {
    try {
      return Enum.valueOf(enumType, rawValue);
    } catch (IllegalArgumentException | NullPointerException exception) {
      throw new BusinessException(CommunityErrorCode.VALIDATION_FAILED);
    }
  }
}
