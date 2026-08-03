package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.UserBlockCommandResult;
import com.ssafy.b209.community.dto.UserBlockResponse;
import com.ssafy.b209.community.service.CommunityUserBlockService;
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

/** 로그인 사용자의 커뮤니티 차단 관계를 관리하는 본인 범위 API다. */
@Validated
@RestController
@RequestMapping("/api/v1/users/me/blocks/{blockedUserId}")
public class CommunityUserBlockController {

  private final CommunityUserBlockService blockService;

  /**
   * @param blockService 차단 관계를 멱등하게 변경하는 서비스
   */
  public CommunityUserBlockController(CommunityUserBlockService blockService) {
    this.blockService = blockService;
  }

  /**
   * 사용자를 차단한다. 이미 차단한 대상이면 현재 상태를 반환한다.
   *
   * @param blockedUserId 차단 대상 사용자 ID
   * @return 신규 차단이면 HTTP 201, 같은 상태 재요청이면 HTTP 200
   */
  @PostMapping
  public ResponseEntity<ApiResponse<UserBlockResponse>> blockUser(
      @PathVariable @Positive Long blockedUserId) {
    UserBlockCommandResult result = blockService.blockUser(blockedUserId);
    ApiResponse<UserBlockResponse> body =
        result.created()
            ? ApiResponse.of(CommonSuccessCode.CREATED, result.response())
            : ApiResponse.ok(result.response());
    return result.created() ? ResponseEntity.status(201).body(body) : ResponseEntity.ok(body);
  }

  /**
   * 사용자 차단을 해제한다. 차단 관계가 없어도 멱등하게 성공한다.
   *
   * @param blockedUserId 차단 해제 대상 사용자 ID
   * @return 본문이 없는 HTTP 204
   */
  @DeleteMapping
  public ResponseEntity<Void> unblockUser(@PathVariable @Positive Long blockedUserId) {
    blockService.unblockUser(blockedUserId);
    return ResponseEntity.noContent().build();
  }
}
