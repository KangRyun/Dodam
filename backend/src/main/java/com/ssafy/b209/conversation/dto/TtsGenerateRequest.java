package com.ssafy.b209.conversation.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.math.BigDecimal;

/**
 * AI 질문 음성 생성 요청 DTO다.
 *
 * <p>음색 카탈로그와 말투 정책은 AI 서버가 소유한다. 말투는 서버가 관리하는 고정 프로필만 허용하며, 기존 클라이언트가 필드를
 * 보내지 않으면 기본 프로필을 사용한다.
 *
 * @param voice 요청 음색 코드(대문자·숫자·밑줄, 최대 50자)
 * @param speed 재생 속도 배율(0.8~1.2)
 * @param toneProfile 캐릭터·상황 말투 프로필
 */
public record TtsGenerateRequest(
    @NotNull @Pattern(regexp = "^[A-Z0-9_]{1,50}$") String voice,
    @NotNull @DecimalMin("0.8") @DecimalMax("1.2") BigDecimal speed,
    TtsToneProfile toneProfile) {

  public TtsGenerateRequest {
    if (toneProfile == null) {
      toneProfile = TtsToneProfile.CHARACTER_DEFAULT_V1;
    }
  }

  public TtsGenerateRequest(String voice, BigDecimal speed) {
    this(voice, speed, TtsToneProfile.CHARACTER_DEFAULT_V1);
  }
}
