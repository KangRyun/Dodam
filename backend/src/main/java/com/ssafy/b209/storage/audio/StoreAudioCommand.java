package com.ssafy.b209.storage.audio;

import java.io.InputStream;

/**
 * 음성 저장 계층으로 전달하는 단일 소비 요청이다.
 *
 * @param inputStream 한 번만 소비할 음성 Byte Stream
 * @param size Multipart가 파싱한 선언 크기(Byte)
 * @param contentType 클라이언트가 전송한 MIME Type
 * @param originalFilename 형식 교차 검증용 파일명이며 저장 key에는 사용하지 않음
 */
public record StoreAudioCommand(
    InputStream inputStream, long size, String contentType, String originalFilename) {}
