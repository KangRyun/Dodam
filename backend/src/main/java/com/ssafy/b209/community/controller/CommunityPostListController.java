package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.PostListPageResponse;
import com.ssafy.b209.community.dto.PostListQuery;
import com.ssafy.b209.community.service.CommunityPostListService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 인증된 사용자가 공개 커뮤니티 게시글 목록을 조회하는 API다. */
@Tag(name = "Community Posts", description = "커뮤니티 게시글 목록 조회 API")
@RestController
@RequestMapping("/api/v1/posts")
public class CommunityPostListController {

  private final CommunityPostListService communityPostListService;

  /**
   * 게시글 목록 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param communityPostListService Query 검증, 권한 범위와 목록 조립을 수행하는 서비스
   */
  public CommunityPostListController(CommunityPostListService communityPostListService) {
    this.communityPostListService = communityPostListService;
  }

  /**
   * 공개·활성 게시글을 필터, 정렬과 페이지 조건으로 조회한다.
   *
   * @param postType 게시글 유형 필터
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @param sort {@code createdAt,desc} 또는 {@code updatedAt,asc} 형식의 정렬 조건
   * @return HTTP 200과 공통 성공 응답으로 감싼 목록 페이지
   * @throws BusinessException 인증이 없거나 Query가 공개 계약을 위반한 경우
   */
  @Operation(summary = "커뮤니티 게시글 목록 조회", description = "ACTIVE·공개·미삭제 게시글만 반환합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "목록 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "인증 필요",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "잘못된 Query Parameter",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<PostListPageResponse>> getPosts(
      @RequestParam(required = false) String postType,
      @RequestParam(required = false) String page,
      @RequestParam(required = false) String size,
      @RequestParam(required = false) String sort) {
    PostListPageResponse response =
        communityPostListService.getPosts(new PostListQuery(postType, page, size, sort));
    return ResponseEntity.ok(ApiResponse.ok(response));
  }
}
