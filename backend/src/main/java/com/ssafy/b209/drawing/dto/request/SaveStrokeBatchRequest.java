package com.ssafy.b209.drawing.dto.request;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * 연속된 캔버스 행동 이벤트를 멱등하게 저장하는 배치를 전달한다.
 *
 * @param batchSequence 세션 내 배치 순번
 * @param firstEventSequence 첫 이벤트 순번
 * @param lastEventSequence 마지막 이벤트 순번
 * @param clientCreatedAt 클라이언트가 배치를 만든 시각
 * @param events 최대 500개의 순서화된 이벤트
 * @param metrics 현재 배치에서 증가한 행동 지표
 */
public record SaveStrokeBatchRequest(
    @Positive int batchSequence,
    @Positive long firstEventSequence,
    @Positive long lastEventSequence,
    @NotNull OffsetDateTime clientCreatedAt,
    @NotEmpty @Size(max = 500) List<@Valid StrokeEventRequest> events,
    @NotNull @Valid StrokeMetricsRequest metrics) {}
