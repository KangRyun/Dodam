package com.ssafy.b209.report.service;

import java.util.Optional;

/**
 * 리포트 PDF 에 실을 이미지를 저장소에서 읽어 오는 경계다.
 *
 * <p>리포트 응답의 그림 URL 은 JWT 인증이 필요한 상대 경로다. 서버가 자기 인증 URL 을 HTTP 로 다시 부르면 인증 토큰을 스스로 만들어야 하고 자기 호출이
 * 실패 지점이 된다. 그래서 저장소를 직접 읽는 경계를 둔다.
 *
 * <p>렌더러(PDFBox·openhtmltopdf 무엇이든)는 이 경계만 알고, 저장 위치·인증·실패 처리는 모른다. 그래서 렌더링 방식을 바꿔도 이 계층은 그대로
 * 쓴다(ADR-0003).
 */
public interface ReportAssetResolver {

  /**
   * 그림 파일 식별자로 PDF 에 실을 이미지를 읽는다.
   *
   * <p>못 읽으면 예외를 던지지 않고 빈 값을 준다. 그림 한 장 때문에 리포트 내보내기 전체가 실패하면 보호자는 아무것도 받지 못한다 — 그림이 빠진 리포트가 없는
   * 리포트보다 낫다.
   *
   * @param drawingAssetId 그림 파일 식별자이며 {@code null} 이면 빈 값
   * @return 실을 수 있는 이미지, 없거나 실을 수 없으면 {@link Optional#empty()}
   */
  Optional<ReportImageAsset> resolveDrawingImage(Long drawingAssetId);
}
