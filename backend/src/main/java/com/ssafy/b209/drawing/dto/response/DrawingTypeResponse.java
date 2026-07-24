package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingActivityCategory;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 아동의 연령과 요청 조건에 따라 노출할 그림 활동 유형을 반환한다.
 *
 * @param drawingTypeId 그림 활동 유형 식별자
 * @param code 클라이언트와 서버가 공유하는 안정적인 업무 코드
 * @param name 사용자에게 표시할 유형 이름
 * @param activityCategory 활동 분류
 * @param selectableBy 유형을 선택할 수 있는 주체
 * @param recommendedAgeMin 권장 최소 만 나이, 제한이 없으면 {@code null}
 * @param recommendedAgeMax 권장 최대 만 나이, 제한이 없으면 {@code null}
 * @param guideText 아동에게 보여줄 안내 문구, 별도 안내가 없으면 {@code null}
 * @param displayOrder 기본 노출 순서
 */
@Schema(description = "그림 활동 유형")
public record DrawingTypeResponse(
    Long drawingTypeId,
    String code,
    String name,
    DrawingActivityCategory activityCategory,
    DrawingTypeSelectableBy selectableBy,
    Integer recommendedAgeMin,
    Integer recommendedAgeMax,
    String guideText,
    int displayOrder) {

  /**
   * 그림 유형 Entity를 외부 응답으로 변환한다.
   *
   * @param drawingType 응답으로 변환할 그림 유형
   * @return 내부 상태를 제외한 그림 유형 응답
   */
  public static DrawingTypeResponse from(DrawingType drawingType) {
    return new DrawingTypeResponse(
        drawingType.getId(),
        drawingType.getCode(),
        drawingType.getName(),
        drawingType.getActivityCategory(),
        drawingType.getSelectableBy(),
        drawingType.getRecommendedAgeMin(),
        drawingType.getRecommendedAgeMax(),
        drawingType.getGuideText(),
        drawingType.getDisplayOrder());
  }
}
