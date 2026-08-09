package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.service.CommunityPostDetailService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 인증된 사용자가 일반 공개 게시글의 전체 본문과 파생 정보를 조회하는 API다. */
@Tag(name = "Community Posts", description = "커뮤니티 게시글 상세 조회 API")
@RestController
@RequestMapping("/api/v1/posts")
public class CommunityPostDetailController {

  private final CommunityPostDetailService communityPostDetailService;

  /**
   * 게시글 상세 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param communityPostDetailService 공개 상태 검증과 상세 DTO 조립을 수행하는 서비스
   */
  public CommunityPostDetailController(CommunityPostDetailService communityPostDetailService) {
    this.communityPostDetailService = communityPostDetailService;
  }

  /**
   * ACTIVE·공개·미삭제 상태인 게시글 상세를 반환한다.
   *
   * @param postId 조회할 양수 게시글 식별자
   * @return HTTP 200과 공통 성공 응답으로 감싼 게시글 상세
   * @throws BusinessException 인증 사용자가 없거나 게시글이 없거나 일반 공개 조건에 맞지 않는 경우
   */
  @Operation(summary = "커뮤니티 게시글 상세 조회", description = "일반 공개 가능한 게시글만 조회합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "게시글 상세 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "인증 필요",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "게시글 없음 또는 일반 공개 조건 불일치",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{postId}")
  public ResponseEntity<ApiResponse<PostDetailResponse>> getPost(
      @PathVariable @Positive Long postId) {
    PostDetailResponse response = communityPostDetailService.getPost(postId);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }
}
