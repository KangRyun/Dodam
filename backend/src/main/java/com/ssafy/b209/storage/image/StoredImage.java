package com.ssafy.b209.storage.image;

/**
 * 이미지 저장 완료 후 후속 서비스가 사용할 안전한 Metadata다.
 *
 * <p>{@code storageKey}는 Storage Root를 제외하고 {@code /}를 구분자로 사용하는 상대 Key다. 서버의 절대 경로나 임시 파일 정보는 포함하지
 * 않는다.
 *
 * @param storageKey Storage Root 기준 상대 Key
 * @param storedFileName 검증된 형식과 UUID로 생성한 파일명
 * @param contentType 실제 이미지 Signature로 검증한 MIME Type
 * @param size 실제 저장된 이미지 크기(Byte)
 * @param checksumSha256 실제 이미지 Byte의 SHA-256 Hex
 */
public record StoredImage(
    String storageKey,
    String storedFileName,
    String contentType,
    long size,
    String checksumSha256) {}
