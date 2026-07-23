package com.ssafy.b209.drawing.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 서버가 수락한 Stroke 배치의 저장 결과를 반환한다.
 *
 * @param batchId 배치 식별자
 * @param batchSequence 세션 내 배치 순번
 * @param acceptedEventCount 저장된 이벤트 수
 * @param lastEventSequence 저장된 마지막 이벤트 순번
 * @param receivedAt 서버 수신 시각
 */
@Schema(description = "Stroke 배치 저장 결과")
public record StrokeBatchResponse(
    Long batchId,
    int batchSequence,
    int acceptedEventCount,
    long lastEventSequence,
    Instant receivedAt) {}
