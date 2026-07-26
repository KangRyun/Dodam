package com.ssafy.b209.notification.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.notification.dto.response.NotificationListPageResponse;
import com.ssafy.b209.notification.dto.response.NotificationReadResponse;
import com.ssafy.b209.notification.service.NotificationQueryService;
import com.ssafy.b209.notification.service.NotificationReadService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * NOTI-03·NOTI-04 알림 목록 조회와 단건 읽음 처리 HTTP API다.
 *
 * <p>이동 경로는 서버가 URL을 만들지 않고 {@code relatedResourceType}·{@code relatedResourceId}로 제공한다. 라우팅은
 * 클라이언트가 결정한다(명세 15.3).
 */
@Tag(name = "Notifications", description = "알림 API")
@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationInboxController {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final NotificationQueryService notificationQueryService;
  private final NotificationReadService notificationReadService;

  /**
   * 인증 경계와 조회·읽음 처리 Use Case를 연결한다.
   *
   * @param currentUserResolver 검증된 Access Token에서 사용자 ID를 해석하는 경계
   * @param notificationQueryService 알림 목록 조회 Use Case
   * @param notificationReadService 단건 읽음 처리 Use Case
   */
  public NotificationInboxController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      NotificationQueryService notificationQueryService,
      NotificationReadService notificationReadService) {
    this.currentUserResolver = currentUserResolver;
    this.notificationQueryService = notificationQueryService;
    this.notificationReadService = notificationReadService;
  }

  /**
   * 수신자의 알림 목록을 최신순으로 조회한다.
   *
   * <p>결과가 없으면 404가 아니라 200과 빈 {@code content}를 반환한다.
   *
   * @param type 조회할 알림 유형이며 미지정 시 전체
   * @param unreadOnly 미열람만 조회할지 여부
   * @param page 0부터 시작하는 페이지
   * @param size 1 이상 100 이하 페이지 크기
   * @return 공통 페이지 형식의 알림 목록 공통 응답
   */
  @Operation(
      summary = "알림 목록 조회",
      description =
          "수신자 본인의 알림을 최신순으로 조회합니다. type으로 유형을 제한하고 unreadOnly로 미열람만 볼 수 있습니다. "
              + "이동 경로는 relatedResourceType과 relatedResourceId로 제공하며 서버가 URL을 만들지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "조회 성공이며 결과가 없으면 빈 목록"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "허용하지 않는 type 또는 페이지 값(COMMON_400_001)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<NotificationListPageResponse>> getNotifications(
      @Parameter(description = "알림 유형") @RequestParam(required = false) String type,
      @Parameter(description = "미열람만 조회") @RequestParam(defaultValue = "false") boolean unreadOnly,
      @Parameter(description = "0부터 시작하는 페이지") @RequestParam(defaultValue = "0") int page,
      @Parameter(description = "페이지 크기") @RequestParam(defaultValue = "20") int size) {
    Long userId = currentUserResolver.requireUserId();
    return ResponseEntity.ok(
        ApiResponse.ok(
            notificationQueryService.getNotifications(userId, type, unreadOnly, page, size)));
  }

  /**
   * 수신자 본인의 알림을 읽음 처리한다.
   *
   * <p>멱등하다. 이미 읽은 알림도 200과 최초 {@code readAt}으로 응답한다. 남의 알림은 존재를 숨기기 위해 404로 응답한다.
   *
   * @param notificationId 읽음 처리할 알림 ID
   * @return 알림 ID와 최초로 읽은 시각 공통 응답
   */
  @Operation(
      summary = "단건 알림 읽음 처리",
      description = "수신자 본인의 알림을 읽음 처리합니다. 재호출은 멱등하며 최초로 읽은 시각을 유지합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "읽음 처리 성공 또는 이미 읽음"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "알림이 없거나 요청자의 알림이 아님(NOTIFICATION_NOT_FOUND)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/{notificationId}/read")
  public ResponseEntity<ApiResponse<NotificationReadResponse>> markNotificationRead(
      @Parameter(description = "읽음 처리할 알림 ID", required = true) @PathVariable Long notificationId) {
    Long userId = currentUserResolver.requireUserId();
    return ResponseEntity.ok(
        ApiResponse.ok(notificationReadService.markRead(userId, notificationId)));
  }
}
