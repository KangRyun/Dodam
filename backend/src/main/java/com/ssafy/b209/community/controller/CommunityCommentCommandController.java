package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.CommentResponse;
import com.ssafy.b209.community.dto.CreateCommentRequest;
import com.ssafy.b209.community.dto.UpdateCommentRequest;
import com.ssafy.b209.community.service.CommunityCommentCommandService;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 커뮤니티 댓글 작성·수정·삭제 REST API를 제공한다. */
@Tag(name = "Community Comments", description = "커뮤니티 댓글 쓰기 API")
@Validated
@RestController
@RequestMapping("/api/v1")
public class CommunityCommentCommandController {

  private final CommunityCommentCommandService service;

  /**
   * 댓글 Application Service를 주입한다.
   *
   * @param service 댓글 작성·수정·삭제 서비스
   */
  public CommunityCommentCommandController(CommunityCommentCommandService service) {
    this.service = service;
  }

  /**
   * 게시글에 댓글을 작성하고 생성된 댓글을 반환한다.
   *
   * @param postId 대상 게시글 ID
   * @param request 댓글 본문과 익명 여부
   * @return HTTP 201과 생성된 댓글
   */
  @Operation(summary = "댓글 작성")
  @PostMapping("/posts/{postId}/comments")
  public ResponseEntity<ApiResponse<CommentResponse>> createComment(
      @PathVariable @Positive Long postId, @Valid @RequestBody CreateCommentRequest request) {
    CommentResponse response = service.createComment(postId, request);
    return ResponseEntity.created(URI.create("/api/v1/comments/" + response.commentId()))
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }

  /**
   * 작성자 본인의 댓글 본문을 수정한다.
   *
   * @param commentId 수정할 댓글 ID
   * @param request 교체할 댓글 본문
   * @return HTTP 200과 수정된 댓글
   */
  @Operation(summary = "댓글 수정")
  @PatchMapping("/comments/{commentId}")
  public ResponseEntity<ApiResponse<CommentResponse>> updateComment(
      @PathVariable @Positive Long commentId, @Valid @RequestBody UpdateCommentRequest request) {
    return ResponseEntity.ok(ApiResponse.ok(service.updateComment(commentId, request)));
  }

  /**
   * 작성자 본인 또는 관리자의 댓글을 삭제한다.
   *
   * @param commentId 삭제할 댓글 ID
   * @return 본문이 없는 HTTP 204 응답
   */
  @Operation(summary = "댓글 삭제")
  @DeleteMapping("/comments/{commentId}")
  public ResponseEntity<Void> deleteComment(@PathVariable @Positive Long commentId) {
    service.deleteComment(commentId);
    return ResponseEntity.noContent().build();
  }
}
