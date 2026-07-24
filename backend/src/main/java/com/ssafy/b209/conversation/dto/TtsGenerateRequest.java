package com.ssafy.b209.conversation.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.math.BigDecimal;

/**
 * AI 질문 음성 생성 요청 DTO다.
 *
 * <p>음색 카탈로그와 말투 정책은 AI 서버가 소유하므로, 이 경계는 안전한 코드 형식과 속도 범위만 검증하고 값을 그대로 전달한다.
 *
 * @param voice 요청 음색 코드(대문자·숫자·밑줄, 최대 50자)
 * @param speed 재생 속도 배율(0.8~1.2)
 */
public record TtsGenerateRequest(
    @NotNull @Pattern(regexp = "^[A-Z0-9_]{1,50}$") String voice,
    @NotNull @DecimalMin("0.8") @DecimalMax("1.2") BigDecimal speed) {}
