package com.ssafy.b209.storage.image;

import java.io.InputStream;

/**
 * 이미지 저장 계층에 전달하는 단일 사용 요청이다.
 *
 * <p>{@code inputStream}의 소유권은 {@link ImageStorage#store(StoreImageCommand)} 호출과 함께 Storage 구현체로
 * 이전된다. 원본 파일명과 Content-Type은 실제 저장 경로가 아니라 이미지 형식 교차 검증에만 사용한다.
 *
 * @param inputStream 한 번만 소비할 이미지 Byte Stream
 * @param size 호출자가 알고 있는 이미지 크기(Byte)
 * @param contentType 호출자가 전달한 이미지 MIME Type
 * @param originalFilename 형식 검증에 참고할 원본 파일명
 */
public record StoreImageCommand(
    InputStream inputStream, long size, String contentType, String originalFilename) {}
