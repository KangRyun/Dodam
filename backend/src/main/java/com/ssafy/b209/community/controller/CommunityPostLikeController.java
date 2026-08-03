package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.PostLikeCommandResult;
import com.ssafy.b209.community.dto.PostLikeResponse;
import com.ssafy.b209.community.service.CommunityPostLikeService;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 보호자와 전문가가 공개 커뮤니티 게시글의 좋아요 상태를 변경하는 API다. */
@Validated
@RestController
@RequestMapping("/api/v1/posts/{postId}/likes")
public class CommunityPostLikeController {

  private final CommunityPostLikeService likeService;

  /**
   * @param likeService 좋아요 상태 변경 서비스
   */
  public CommunityPostLikeController(CommunityPostLikeService likeService) {
    this.likeService = likeService;
  }

  /**
   * 게시글에 좋아요를 등록한다. 이미 등록된 경우 기존 상태와 집계값을 반환한다.
   *
   * @param postId 대상 게시글 ID
   * @return 신규 등록이면 HTTP 201, 동일 상태 재요청이면 HTTP 200
   */
  @PostMapping
  public ResponseEntity<ApiResponse<PostLikeResponse>> likePost(
      @PathVariable @Positive Long postId) {
    PostLikeCommandResult result = likeService.likePost(postId);
    ApiResponse<PostLikeResponse> body =
        result.created()
            ? ApiResponse.of(CommonSuccessCode.CREATED, result.response())
            : ApiResponse.ok(result.response());
    return result.created() ? ResponseEntity.status(201).body(body) : ResponseEntity.ok(body);
  }

  /**
   * 게시글 좋아요를 취소한다. 등록된 좋아요가 없어도 멱등하게 성공한다.
   *
   * @param postId 대상 게시글 ID
   * @return 본문이 없는 HTTP 204 응답
   */
  @DeleteMapping
  public ResponseEntity<Void> unlikePost(@PathVariable @Positive Long postId) {
    likeService.unlikePost(postId);
    return ResponseEntity.noContent().build();
  }
}
