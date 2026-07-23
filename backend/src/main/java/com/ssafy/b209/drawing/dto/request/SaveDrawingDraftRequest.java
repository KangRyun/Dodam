package com.ssafy.b209.drawing.dto.request;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.OffsetDateTime;

/**
 * 현재 캔버스 미리보기와 함께 전달되는 복구 기준 Metadata다.
 *
 * @param lastEventSequence 미리보기에 반영된 마지막 그림 이벤트 순서
 * @param clientSavedAt Offset을 포함한 클라이언트 저장 시각
 */
public record SaveDrawingDraftRequest(
    @Positive long lastEventSequence, @NotNull OffsetDateTime clientSavedAt) {}
