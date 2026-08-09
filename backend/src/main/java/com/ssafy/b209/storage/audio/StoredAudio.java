package com.ssafy.b209.storage.audio;

/**
 * 최종 보관된 음성 파일의 안전한 내부 메타데이터다.
 *
 * @param storageKey Storage Root 기준 상대 key
 * @param contentType Signature와 컨테이너로 확인한 MIME Type
 * @param size 실제 파일 크기(Byte)
 * @param checksumSha256 실제 음성 Byte의 SHA-256 Hex
 * @param durationMillis 검증된 실제 길이(ms)
 */
public record StoredAudio(
    String storageKey, String contentType, long size, String checksumSha256, long durationMillis) {}
