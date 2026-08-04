package com.ssafy.b209.drawing.dto.request;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import java.time.OffsetDateTime;

/**
 * 현재 캔버스 미리보기와 함께 전달되는 복구 기준 Metadata다.
 *
 * @param lastEventSequence 미리보기에 반영된 마지막 그림 이벤트 순서이며, 채우기·전체 지우기처럼 이벤트를 만들지 않는 변경만 있는 문서는 {@code
 *     0}이다
 * @param clientSavedAt Offset을 포함한 클라이언트 저장 시각이며, 같은 이벤트 순서에서는 이 값이 초안의 최신 여부를 결정한다
 */
public record SaveDrawingDraftRequest(
    @PositiveOrZero long lastEventSequence, @NotNull OffsetDateTime clientSavedAt) {}
