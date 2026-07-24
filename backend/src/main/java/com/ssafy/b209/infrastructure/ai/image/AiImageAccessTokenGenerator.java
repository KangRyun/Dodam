package com.ssafy.b209.infrastructure.ai.image;

/** AI 서버의 일회성 이미지 조회 URL에 사용할 추측 불가능한 Token을 생성한다. */
public interface AiImageAccessTokenGenerator {

  /**
   * URL 경로에 바로 사용할 수 있는 Token을 생성한다.
   *
   * @return URL-safe Base64 형식의 불투명 Token
   */
  String generate();
}
