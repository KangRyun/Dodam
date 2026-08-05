package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 보호자에게 열린 관찰 특징 한 건이다.
 *
 * <p>검토를 통과한({@code REVIEWED_GUARDIAN}) 항목만 담긴다. 보호자에게 바로 열지 않는 {@code EXPERT_ONLY} 항목은 <b>응답에 아예
 * 실리지 않는다</b> — FE 가 숨기는 방식이 아니다.
 *
 * <p>{@code featureCode}(예: {@code HOUSE_CENTER})는 담지 않는다. 화면에 쓰지 않는 내부 코드이고, 응답에 실리면 언젠가 표시될 여지가
 * 생긴다. 항목 식별은 배열 순서로 충분하다.
 *
 * @param title 관찰 제목이며 없으면 {@code null}
 * @param description 관찰 내용
 * @param evidenceSummary 관찰 근거 요약이며 없으면 {@code null}
 */
@Schema(description = "보호자에게 열린 관찰 특징")
public record ReportObservedFeatureResponse(
    String title, String description, String evidenceSummary) {}
