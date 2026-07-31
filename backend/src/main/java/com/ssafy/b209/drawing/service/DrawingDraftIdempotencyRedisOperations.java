package com.ssafy.b209.drawing.service;

import java.time.Duration;

/** Redis 원자 연산을 Draft 멱등성 정책에서 분리하는 내부 경계다. */
interface DrawingDraftIdempotencyRedisOperations {

  DrawingDraftIdempotencyClaim claim(String redisKey, String fingerprint, Duration processingTtl);

  boolean complete(String redisKey, String fingerprint, String responseJson, Duration completedTtl);

  void release(String redisKey, String fingerprint);
}

enum DrawingDraftIdempotencyClaimStatus {
  CLAIMED,
  COMPLETED,
  PROCESSING,
  REUSED
}

record DrawingDraftIdempotencyClaim(
    DrawingDraftIdempotencyClaimStatus status, String responseJson) {

  static DrawingDraftIdempotencyClaim claimed() {
    return new DrawingDraftIdempotencyClaim(DrawingDraftIdempotencyClaimStatus.CLAIMED, null);
  }

  static DrawingDraftIdempotencyClaim processing() {
    return new DrawingDraftIdempotencyClaim(DrawingDraftIdempotencyClaimStatus.PROCESSING, null);
  }

  static DrawingDraftIdempotencyClaim reused() {
    return new DrawingDraftIdempotencyClaim(DrawingDraftIdempotencyClaimStatus.REUSED, null);
  }

  static DrawingDraftIdempotencyClaim completed(String responseJson) {
    return new DrawingDraftIdempotencyClaim(
        DrawingDraftIdempotencyClaimStatus.COMPLETED, responseJson);
  }
}
