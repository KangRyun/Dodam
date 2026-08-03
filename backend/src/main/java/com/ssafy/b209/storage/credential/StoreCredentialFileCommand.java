package com.ssafy.b209.storage.credential;

/**
 * 전문가 자격 증빙 Storage에 전달하는 제한된 파일 내용과 선언 Metadata다.
 *
 * @param content 최대 크기 검사를 거친 파일 Byte
 * @param contentType Client가 선언한 MIME Type
 * @param originalFilename Client가 전달한 원본 파일명
 */
public record StoreCredentialFileCommand(
    byte[] content, String contentType, String originalFilename) {}
