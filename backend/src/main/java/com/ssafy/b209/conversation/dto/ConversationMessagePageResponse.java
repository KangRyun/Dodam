package com.ssafy.b209.conversation.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 대화 내역 메시지 목록과 페이지 메타데이터를 공통 페이지 형식으로 반환한다.
 *
 * @param content 순번 오름차순으로 정렬된 현재 페이지 메시지 목록
 * @param page 0부터 시작하는 현재 페이지
 * @param size 요청한 페이지 크기
 * @param totalElements 조건에 맞는 전체 메시지 수
 * @param totalPages 전체 페이지 수
 * @param first 첫 페이지 여부
 * @param last 마지막 페이지 여부
 * @param hasNext 다음 페이지 존재 여부
 */
@Schema(description = "대화 내역 메시지 목록 페이지")
public record ConversationMessagePageResponse(
    List<ConversationMessageResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    boolean hasNext) {}
