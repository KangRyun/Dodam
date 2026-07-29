package com.ssafy.b209.analysis.dto;

import java.math.BigDecimal;

/**
 * 공개 분석 조회에서 사용하는 0~1 정규화 객체 영역이다.
 *
 * @param x 이미지 너비를 기준으로 정규화한 좌측 상단 X 좌표
 * @param y 이미지 높이를 기준으로 정규화한 좌측 상단 Y 좌표
 * @param width 이미지 너비를 기준으로 정규화한 객체 영역 너비
 * @param height 이미지 높이를 기준으로 정규화한 객체 영역 높이
 */
public record AnalysisBoundingBoxResponse(
    BigDecimal x, BigDecimal y, BigDecimal width, BigDecimal height) {}
