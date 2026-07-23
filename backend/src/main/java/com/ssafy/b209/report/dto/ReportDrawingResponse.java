package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 리포트에 노출할 그림 이미지의 공개 URL을 반환한다.
 *
 * @param finalImageUrl 최종 그림 이미지 URL이며 없으면 {@code null}
 * @param thumbnailUrl 썸네일 이미지 URL이며 없으면 {@code null}
 */
@Schema(description = "리포트 그림 이미지 URL")
public record ReportDrawingResponse(String finalImageUrl, String thumbnailUrl) {}
