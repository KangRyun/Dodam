package com.ssafy.b209.community.repository;

/**
 * DB v1.2 {@code community_post_template_fields}의 조회 전용 항목이다.
 *
 * @param fieldCode Template 필드 코드
 * @param valueType DB 값 유형
 * @param valueText DB 문자열 원문
 * @param displayOrder 게시글 내 노출 순서
 */
public record CommunityPostTemplateFieldRow(
    String fieldCode, String valueType, String valueText, int displayOrder) {}
