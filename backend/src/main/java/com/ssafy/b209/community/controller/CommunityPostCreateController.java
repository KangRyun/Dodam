package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.CreatePostRequest;
import com.ssafy.b209.community.dto.PostDetailResponse;
import com.ssafy.b209.community.service.CommunityPostCreateService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 인증된 사용자가 커뮤니티 게시글을 작성하는 API다.
 *
 * <p>요청 형식 검증과 공통 응답 조립만 담당하고, 유형별 작성 권한과 저장 규칙은 {@link CommunityPostCreateService}에 위임한다.
 */
@Tag(name = "Community Posts", description = "커뮤니티 게시글 작성 API")
@RestController
@RequestMapping("/api/v1/posts")
public class CommunityPostCreateController {

  private final CommunityPostCreateService communityPostCreateService;

  /**
   * 게시글 작성 Application Service를 사용하는 Controller를 생성한다.
   *
   * @param communityPostCreateService 권한 검증과 게시글 저장을 수행하는 서비스
   */
  public CommunityPostCreateController(CommunityPostCreateService communityPostCreateService) {
    this.communityPostCreateService = communityPostCreateService;
  }

  /**
   * 새 커뮤니티 게시글을 활성·공개 상태로 생성한다.
   *
   * @param request 작성할 게시글 정보
   * @return HTTP 201, 생성된 게시글의 Location Header와 공통 성공 응답으로 감싼 상세
   * @throws BusinessException 인증 사용자가 없거나 해당 유형을 작성할 권한이 없는 경우
   */
  @Operation(summary = "커뮤니티 게시글 작성", description = "유형별 작성 권한을 검증한 뒤 게시글을 생성합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "게시글 작성 성공"),
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
        description = "해당 게시글 유형 작성 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<PostDetailResponse>> createPost(
      @Valid @RequestBody CreatePostRequest request) {
    PostDetailResponse response = communityPostCreateService.createPost(request);
    URI location = URI.create("/api/v1/posts/" + response.postId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
