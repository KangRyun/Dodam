package com.ssafy.b209.analysis.dto;

import java.math.BigDecimal;

/**
 * 공개 분석 조회에 포함되는 객체 탐지 결과다.
 *
 * @param detectedObjectId 저장된 탐지 객체 식별자
 * @param objectCode AI 계약에서 사용하는 객체 코드
 * @param objectName 사용자 표시용 객체명이며 저장되지 않았으면 {@code null}
 * @param confidence 0~1 범위의 탐지 신뢰도
 * @param boundingBox 0~1 범위로 정규화한 객체 영역
 */
public record AnalysisDetectedObjectResponse(
    Long detectedObjectId,
    String objectCode,
    String objectName,
    BigDecimal confidence,
    AnalysisBoundingBoxResponse boundingBox) {}
