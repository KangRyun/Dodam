package com.ssafy.b209.infrastructure.ai.tts;

import com.ssafy.b209.conversation.dto.TtsToneProfile;
import java.math.BigDecimal;

/**
 * 질문 텍스트 합성 Client에 전달하는 요청이다.
 *
 * <p>말투 문구 자체는 AI 서버가 소유하며, 이 경계는 검증된 고정 프로필 식별자만 전달한다.
 *
 * @param text 합성할 질문 텍스트
 * @param voice 요청 음색 코드
 * @param speed 재생 속도 배율(0.8~1.2)
 * @param toneProfile 서버 고정 캐릭터·상황 말투 프로필
 */
public record TtsSynthesisCommand(
    String text, String voice, BigDecimal speed, TtsToneProfile toneProfile) {}
