package com.ssafy.b209.infrastructure.ai.drawing;

import java.net.URI;

/**
 * 실제 이미지 접근 방식이 구성되지 않았을 때 외부 호출을 차단하는 Provider다.
 *
 * <p>S15P11B209-372에서 짧은 만료의 읽기 전용 URL 발급 방식이 연결되기 전까지 저장소 Key나 서버 절대 경로가 AI 서버로 유출되는 것을 방지한다.
 */
public final class UnavailableDrawingAnalysisImageUrlProvider
    implements DrawingAnalysisImageUrlProvider {

  /**
   * 구성되지 않은 이미지 접근 요청을 네트워크 호출 전에 거부한다.
   *
   * @param storageKey 외부에 노출하지 않는 이미지 저장소 상대 Key
   * @return 정상 구성 전에는 반환하지 않음
   * @throws DrawingAnalysisClientException 항상 요청 실패로 발생
   */
  @Override
  public URI createReadUrl(String storageKey) {
    throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
  }
}
