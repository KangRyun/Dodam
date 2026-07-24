package com.ssafy.b209.storage.audio;

import java.util.Locale;

/**
 * 저장된 음성 파일의 프록시 재생 응답에 실을 Content-Type을 storage key 확장자에서 결정한다.
 *
 * <p>DB에는 별도의 MIME 컬럼이 없고 저장 key의 확장자가 곧 저장 당시 확정된 컨테이너다. 허용된 음성 형식 규칙({@link AudioFormat})을 단일 근거로
 * 재사용하며, 알 수 없는 확장자는 {@link #DEFAULT_CONTENT_TYPE}으로 안전하게 내려준다. storage key 원문은 응답·로그에 노출하지 않는다.
 */
public final class AudioContentTypeResolver {

  /** 확장자로 형식을 판별할 수 없을 때 사용하는 안전한 기본 Content-Type이다. */
  public static final String DEFAULT_CONTENT_TYPE = "application/octet-stream";

  private AudioContentTypeResolver() {}

  /**
   * storage key의 확장자로 재생 응답 Content-Type을 결정한다.
   *
   * @param storageKey 288이 저장한 Root-relative 음성 key
   * @return 형식에 맞는 표준 Content-Type 또는 판별 불가 시 {@link #DEFAULT_CONTENT_TYPE}
   */
  public static String resolveFromStorageKey(String storageKey) {
    if (storageKey == null || storageKey.isBlank()) {
      return DEFAULT_CONTENT_TYPE;
    }
    int dot = storageKey.lastIndexOf('.');
    if (dot < 0 || dot == storageKey.length() - 1) {
      return DEFAULT_CONTENT_TYPE;
    }
    String extension = storageKey.substring(dot + 1).toLowerCase(Locale.ROOT);
    String contentType = AudioFormat.contentTypeForExtension(extension);
    return contentType == null ? DEFAULT_CONTENT_TYPE : contentType;
  }
}
