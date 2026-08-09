package com.ssafy.b209.conversation.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * AI 질문 음성 생성·조회 응답 DTO다.
 *
 * <p>{@code audioUrl}은 presigned URL이 아니라 매 요청 인증·소유권을 검증하는 프록시 스트리밍 상대 경로다. 프록시 스트리밍이라 실제 만료가 없어
 * {@code expiresAt}은 항상 {@code null}이다. 내부 저장 key·절대 경로는 담지 않는다.
 *
 * @param audioUrl 음성 재생 프록시 상대 경로
 * @param expiresAt 만료 시각(프록시 스트리밍이라 항상 {@code null})
 * @param durationMs 재생 길이(ms). 캐시 히트로 재계산하지 않은 경우 {@code null}
 * @param subtitle 자막으로 사용할 질문 원문
 */
@Schema(description = "AI 질문 음성 생성 응답")
public record TtsGenerateResponse(
    String audioUrl, Instant expiresAt, Long durationMs, String subtitle) {}
