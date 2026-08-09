package com.ssafy.b209.storage.credential;

/**
 * 검증과 저장을 완료한 전문가 자격 증빙 파일 Metadata다.
 *
 * @param storageKey Storage Root 또는 Prefix 기준 상대 Key
 * @param storageKeyHash Storage Key의 SHA-256 Hex
 * @param contentType Signature로 판정한 MIME Type
 * @param size 실제 파일 크기
 */
public record StoredCredentialFile(
    String storageKey, String storageKeyHash, String contentType, long size) {}
