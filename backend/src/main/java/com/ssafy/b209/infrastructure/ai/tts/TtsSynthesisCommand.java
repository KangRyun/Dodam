package com.ssafy.b209.infrastructure.ai.tts;

import java.math.BigDecimal;

/**
 * 질문 텍스트 합성 Client에 전달하는 요청이다.
 *
 * <p>음색 카탈로그와 말투 정책은 AI 서버가 소유하며, 이 경계는 검증된 값을 그대로 전달만 한다.
 *
 * @param text 합성할 질문 텍스트
 * @param voice 요청 음색 코드
 * @param speed 재생 속도 배율(0.8~1.2)
 */
public record TtsSynthesisCommand(String text, String voice, BigDecimal speed) {}
