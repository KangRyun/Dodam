package com.ssafy.b209.infrastructure.ai.drawing;

import java.net.URI;

/**
 * 이미지 저장소 상대 Key를 AI 서버가 읽을 수 있는 제한된 URL로 변환하는 경계다.
 *
 * <p>구현체는 서버 절대 경로 또는 영구 공개 URL을 반환해서는 안 된다.
 */
@FunctionalInterface
public interface DrawingAnalysisImageUrlProvider {

  /**
   * 분석 대상 이미지를 읽을 수 있는 URL을 생성한다.
   *
   * @param storageKey 이미지 저장소의 안전한 상대 Key
   * @return AI 서버에서 접근 가능한 짧은 만료의 읽기 전용 URL
   * @throws DrawingAnalysisClientException 안전한 URL을 만들 수 없는 경우
   */
  URI createReadUrl(String storageKey);
}
