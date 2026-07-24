package com.ssafy.b209.conversation.service;

import com.ssafy.b209.storage.audio.OpenedAudio;

/**
 * 음성 답변 원본을 프록시 스트리밍하기 위해 서비스가 조립한 재생 자원이다.
 *
 * <p>인증·소유권 검증과 원본 존재 확인을 통과한 뒤 열린 읽기 전용 Stream과 응답 Content-Type만 담는다. 내부 저장 key·절대 경로는 포함하지 않으며,
 * Stream은 Controller가 스트리밍을 마친 뒤 {@link OpenedAudio#close()}로 닫는다.
 *
 * @param contentType 재생 응답에 사용할 표준 Content-Type
 * @param audio 스트리밍 후 닫아야 하는 저장된 음성 Stream
 */
public record VoiceAnswerAudioResource(String contentType, OpenedAudio audio) {}
