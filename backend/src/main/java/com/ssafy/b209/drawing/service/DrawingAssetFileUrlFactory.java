package com.ssafy.b209.drawing.service;

import java.util.Objects;
import org.springframework.stereotype.Component;

/**
 * 그림 파일을 인증된 API로 조회할 수 있는 상대 URL을 생성한다.
 *
 * <p>Storage Key나 서버 절대 경로를 API 응답에 노출하지 않고, Draft 조회와 활성 세션 조회가 동일한 파일 조회 계약을 사용하도록 한다.
 */
@Component
public class DrawingAssetFileUrlFactory {

  private static final String FILE_URL_TEMPLATE = "/api/v1/drawing-assets/%d/file";

  /**
   * 그림 파일 식별자를 인증이 필요한 상대 조회 URL로 변환한다.
   *
   * @param drawingAssetId 그림 파일 식별자
   * @return 클라이언트가 API Base URL에 결합해 사용할 상대 URL
   * @throws NullPointerException 그림 파일 식별자가 {@code null}인 경우
   */
  public String create(Long drawingAssetId) {
    return FILE_URL_TEMPLATE.formatted(Objects.requireNonNull(drawingAssetId, "drawingAssetId"));
  }
}
