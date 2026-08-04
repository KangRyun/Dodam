package com.ssafy.b209.user.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 보호자 PIN 상태 응답이다 (S15P11B209-879).
 *
 * <p>상태 조회·설정·변경·검증 성공·검증 실패가 <b>모두 같은 모양</b>이다. 실패 응답에도 같은 값을 실어야 클라이언트가 "몇 번 남았는지"를 별도 조회 없이 화면에
 * 쓸 수 있다.
 *
 * <p>PIN 원문·해시는 어떤 필드에도 담지 않는다.
 *
 * <p>{@code serverTime} 을 함께 주는 이유는 기기 시계를 믿을 수 없기 때문이다. 잠금이 언제 풀리는지 계산할 때 클라이언트가 자기 시계와 서버 시계의 차이를
 * 보정할 수 있어야 한다. 시각은 UTC ISO-8601 {@code Z} 표기다(S15P11B209-822).
 *
 * @param pinConfigured PIN 이 설정돼 있는지
 * @param locked 지금 잠겨 있는지
 * @param remainingAttempts 잠기기 전까지 남은 시도 횟수이며 잠금 중이면 0
 * @param retryAfterSeconds 잠금 해제까지 남은 초이며 잠금 중이 아니면 {@code null}
 * @param lockedUntil 잠금 해제 시각(UTC)이며 잠금 중이 아니면 {@code null}
 * @param serverTime 응답을 만든 서버 시각(UTC)
 */
@Schema(description = "보호자 PIN 상태")
public record GuardianPinStatusResponse(
    @Schema(description = "PIN 설정 여부", example = "true") boolean pinConfigured,
    @Schema(description = "잠금 여부", example = "false") boolean locked,
    @Schema(description = "남은 시도 횟수", example = "5") int remainingAttempts,
    @Schema(description = "잠금 해제까지 남은 초", example = "30") Long retryAfterSeconds,
    @Schema(description = "잠금 해제 시각(UTC)") Instant lockedUntil,
    @Schema(description = "서버 시각(UTC)") Instant serverTime) {}
