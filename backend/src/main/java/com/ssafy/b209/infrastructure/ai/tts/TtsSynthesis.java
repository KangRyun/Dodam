package com.ssafy.b209.infrastructure.ai.tts;

/**
 * 질문 TTS 합성 Client가 반환하는 음성 결과다.
 *
 * <p>재생 길이는 저장 계층이 실제 Byte에서 검증·계산하므로 이 결과에 담지 않는다. 음성 Byte는 로그에 남기지 않는다.
 *
 * @param audio 합성된 음성 Byte
 * @param audioFormat 컨테이너 형식 문자열(예: {@code mp3})
 */
public record TtsSynthesis(byte[] audio, String audioFormat) {}
