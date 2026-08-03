package com.ssafy.b209.community.dto;

import com.ssafy.b209.community.domain.CommunityAttachmentType;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 공개 게시글에 연결된 첨부 이미지 정보다.
 *
 * @param fileId 외부 파일 ID
 * @param type 첨부 유형
 * @param url JWT 인증이 필요한 상대 조회 URL
 * @param widthPx 이미지 너비
 * @param heightPx 이미지 높이
 */
@Schema(description = "커뮤니티 게시글 첨부 이미지")
public record CommunityAttachmentResponse(
    String fileId, CommunityAttachmentType type, String url, Integer widthPx, Integer heightPx) {}
