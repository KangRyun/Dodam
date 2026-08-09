package com.ssafy.b209.drawing.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 그림 활동을 시작할 때 선택적으로 전달하는 캔버스 표시 설정이다.
 *
 * @param width 캔버스 너비
 * @param height 캔버스 높이
 * @param backgroundColor 캔버스 배경색
 */
public record CanvasConfigurationRequest(
    @Schema(description = "캔버스 너비", example = "1920") Integer width,
    @Schema(description = "캔버스 높이", example = "1080") Integer height,
    @Schema(description = "캔버스 배경색", example = "#FFFFFF") String backgroundColor) {}
