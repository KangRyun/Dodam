package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.dto.UpdatePostRequest;
import com.ssafy.b209.community.service.CommunityPostCommandService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 인증된 사용자가 커뮤니티 게시글을 수정·삭제하는 API다.
 *
 * <p>요청 형식 검증과 공통 응답 조립만 담당하고, 권한 판정과 상태 변경은 {@link CommunityPostCommandService}에 위임한다.
 */
@Tag(name = "Community Posts", description = "커뮤니티 게시글 수정·삭제 API")
@Validated
@RestController
@RequestMapping("/api/v1/posts")
public class CommunityPostCommandController {

  private final CommunityPostCommandService communityPostCommandService;

  /**
   * 게시글 수정·삭제 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param communityPostCommandService 권한 검증과 게시글 상태 변경을 수행하는 서비스
   */
  public CommunityPostCommandController(CommunityPostCommandService communityPostCommandService) {
    this.communityPostCommandService = communityPostCommandService;
  }

  /**
   * 작성자 본인의 게시글을 새 값으로 교체한다.
   *
   * @param postId 수정할 게시글 식별자
   * @param request 교체할 게시글 정보
   * @return HTTP 200, 공통 성공 응답으로 감싼 수정된 게시글 상세
   * @throws BusinessException 인증 사용자가 없거나, 게시글이 없거나, 작성자 본인이 아니거나, 바꾸려는 유형을 작성할 권한이 없는 경우
   */
  @Operation(summary = "커뮤니티 게시글 수정", description = "작성자 본인의 게시글을 전체 교체하고 유형 변경 시 작성 권한을 다시 검증합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "게시글 수정 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "인증 필요",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "게시글 수정 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "게시글을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/{postId}")
  public ResponseEntity<ApiResponse<PostDetailResponse>> updatePost(
      @Parameter(description = "수정할 게시글 식별자", required = true) @PathVariable @Positive Long postId,
      @Valid @RequestBody UpdatePostRequest request) {
    PostDetailResponse response = communityPostCommandService.updatePost(postId, request);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  /**
   * 작성자 본인 또는 관리자의 요청으로 게시글을 삭제 상태로 전환한다.
   *
   * @param postId 삭제할 게시글 식별자
   * @return 본문이 없는 HTTP 204 응답
   * @throws BusinessException 인증 사용자가 없거나, 게시글이 없거나, 작성자 본인도 관리자도 아닌 경우
   */
  @Operation(summary = "커뮤니티 게시글 삭제", description = "작성자 본인 또는 관리자의 게시글을 Soft Delete합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "204",
        description = "게시글 삭제 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "인증 필요",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "게시글 삭제 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "게시글을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping("/{postId}")
  public ResponseEntity<Void> deletePost(
      @Parameter(description = "삭제할 게시글 식별자", required = true) @PathVariable @Positive
          Long postId) {
    communityPostCommandService.deletePost(postId);
    return ResponseEntity.noContent().build();
  }
}
