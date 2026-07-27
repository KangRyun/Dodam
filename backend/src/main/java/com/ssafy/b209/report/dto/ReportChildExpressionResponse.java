package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 아동이 직접 표현한 감정 선택과 발화를 반환한다.
 *
 * @param selectedEmotions 아동이 선택한 감정 코드 목록
 * @param expressedEmotionText 아동이 표현한 감정 내용이며 없으면 {@code null}
 * @param representativeUtterances 대표 발화 목록
 */
@Schema(description = "아동 표현")
public record ReportChildExpressionResponse(
    List<String> selectedEmotions,
    String expressedEmotionText,
    List<ReportUtteranceResponse> representativeUtterances) {}
