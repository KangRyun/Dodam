package com.ssafy.b209.community.dto;

import java.time.Instant;

/**
 * 커뮤니티 첨부 이미지 사전 업로드 결과다.
 *
 * @param fileId 게시글 요청에 전달할 외부 파일 ID
 * @param contentType 검증된 MIME Type
 * @param size 저장된 이미지 크기(Byte)
 * @param widthPx 이미지 너비
 * @param heightPx 이미지 높이
 * @param expiresAt 게시글 연결 전 임시 파일 만료 시각
 */
public record CommunityAttachmentUploadResponse(
    String fileId,
    String contentType,
    long size,
    Integer widthPx,
    Integer heightPx,
    Instant expiresAt) {}
