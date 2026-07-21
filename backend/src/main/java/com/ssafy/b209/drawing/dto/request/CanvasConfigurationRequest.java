package com.ssafy.b209.drawing.dto.request;

/**
 * 그림 활동을 시작할 때 선택적으로 전달하는 캔버스 표시 설정이다.
 *
 * @param width 캔버스 너비
 * @param height 캔버스 높이
 * @param backgroundColor 캔버스 배경색
 */
public record CanvasConfigurationRequest(Integer width, Integer height, String backgroundColor) {}
