package com.ssafy.b209.drawing.service;

import java.util.Objects;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

/**
 * 그림 파일을 인증된 API로 조회할 수 있는 상대 URL을 생성한다.
 *
 * <p>Storage Key나 서버 절대 경로를 API 응답에 노출하지 않고, Draft 조회와 활성 세션 조회가 동일한 파일 조회 계약을 사용하도록 한다.
 */
@Component
public class DrawingAssetFileUrlFactory {

  private static final String FILE_URL_TEMPLATE = "/api/v1/drawing-assets/%d/file";
  private static final Pattern FILE_URL_PATTERN =
      Pattern.compile("/api/v1/drawing-assets/([0-9]+)/file");

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

  /**
   * {@link #create(Long)} 가 만든 URL 에서 그림 파일 식별자를 되읽는다.
   *
   * <p>리포트 응답은 그림을 URL 로만 노출한다(계약). 서버가 PDF 에 그림을 실을 때는 그 URL 을 HTTP 로 다시 부르지 않고 저장소에서 바로 읽는데, 그러려면
   * 식별자가 필요하다. URL 형식을 아는 곳을 이 클래스 하나로 묶어 두기 위해 되읽기도 여기에 둔다 — 파싱을 호출부마다 두면 형식이 바뀔 때 조용히 깨진다.
   *
   * @param fileUrl {@link #create(Long)} 형식의 상대 URL 이며 {@code null} 이거나 형식이 다르면 빈 값
   * @return 그림 파일 식별자
   */
  public Optional<Long> parseAssetId(String fileUrl) {
    if (fileUrl == null) return Optional.empty();
    Matcher matcher = FILE_URL_PATTERN.matcher(fileUrl);
    if (!matcher.matches()) return Optional.empty();
    try {
      return Optional.of(Long.parseLong(matcher.group(1)));
    } catch (NumberFormatException exception) {
      return Optional.empty();
    }
  }
}
