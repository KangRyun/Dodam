package com.ssafy.b209.community.dto;

import com.ssafy.b209.storage.image.StoredImageContent;

/**
 * 인증된 첨부 이미지 조회에 사용할 Storage Stream과 캐시 상태다.
 *
 * @param content 닫기 책임을 포함한 이미지 Stream
 * @param immutable 게시글 연결이 끝나 장기 캐시할 수 있는지 여부
 */
public record CommunityAttachmentFileResource(StoredImageContent content, boolean immutable) {}
