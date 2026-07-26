package com.ssafy.b209.notification.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 공통 페이지 형식으로 알림 목록과 페이지 메타데이터를 반환한다.
 *
 * <p>결과가 없으면 404가 아니라 200과 빈 {@code content}를 반환한다. 커뮤니티 목록과 같은 형식을 사용해 클라이언트가 페이지 처리를 한 번만 구현하게
 * 한다.
 *
 * @param content 현재 페이지의 알림 목록
 * @param page 0부터 시작하는 현재 페이지
 * @param size 요청한 페이지 크기
 * @param totalElements 전체 조건 일치 건수
 * @param totalPages 전체 페이지 수
 * @param first 첫 페이지 여부
 * @param last 마지막 페이지 여부
 * @param hasNext 다음 페이지 존재 여부
 */
@Schema(description = "알림 목록 페이지")
public record NotificationListPageResponse(
    List<NotificationListItemResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    boolean hasNext) {}
