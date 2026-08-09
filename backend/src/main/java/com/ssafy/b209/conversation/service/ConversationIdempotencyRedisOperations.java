package com.ssafy.b209.conversation.service;

import java.time.Duration;

/** Redis Lua 연산을 대화 시작 멱등성 정책으로부터 분리하는 내부 경계다. */
interface ConversationIdempotencyRedisOperations {

  IdempotencyClaim claim(String redisKey, String fingerprint, Duration processingTtl);

  boolean complete(
      String redisKey,
      String fingerprint,
      StoredConversationHttpResponse response,
      Duration responseTtl);
}

enum IdempotencyClaimStatus {
  CLAIMED,
  COMPLETED,
  PROCESSING,
  REUSED
}

record IdempotencyClaim(IdempotencyClaimStatus status, StoredConversationHttpResponse response) {
  static IdempotencyClaim claimed() {
    return new IdempotencyClaim(IdempotencyClaimStatus.CLAIMED, null);
  }

  static IdempotencyClaim processing() {
    return new IdempotencyClaim(IdempotencyClaimStatus.PROCESSING, null);
  }

  static IdempotencyClaim reused() {
    return new IdempotencyClaim(IdempotencyClaimStatus.REUSED, null);
  }

  static IdempotencyClaim completed(StoredConversationHttpResponse response) {
    return new IdempotencyClaim(IdempotencyClaimStatus.COMPLETED, response);
  }
}

/** Redis에 저장하는 최초 HTTP 응답 Snapshot이다. */
record StoredConversationHttpResponse(int status, String location, String body) {}
