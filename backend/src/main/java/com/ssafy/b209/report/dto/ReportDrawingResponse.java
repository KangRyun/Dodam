package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 리포트에 노출할 그림 이미지의 인증된 상대 URL을 반환한다.
 *
 * @param finalImageUrl JWT 인증이 필요한 최종 그림 상대 URL이며 없으면 {@code null}
 * @param thumbnailUrl JWT 인증이 필요한 미리보기 상대 URL. 별도 썸네일이 없으면 FINAL URL과 같으며, 그림 파일이 없으면 {@code null}
 */
@Schema(description = "리포트 그림 이미지 URL")
public record ReportDrawingResponse(String finalImageUrl, String thumbnailUrl) {}
