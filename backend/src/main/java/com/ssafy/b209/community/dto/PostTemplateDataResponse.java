package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * DB v1.2의 게시글 Template 항목 한 건을 원문 손실 없이 전달한다.
 *
 * @param fieldCode Template 필드 코드
 * @param valueType DB에 저장된 값 유형
 * @param value DB {@code value_text} 문자열 원문
 * @param displayOrder 게시글 내 노출 순서
 */
@Schema(description = "게시글 Template 데이터 항목")
public record PostTemplateDataResponse(
    @Schema(description = "Template 필드 코드") String fieldCode,
    @Schema(description = "DB에 저장된 값 유형") String valueType,
    @Schema(description = "DB value_text 원문 문자열") String value,
    @Schema(description = "게시글 내 노출 순서") int displayOrder) {}
