package com.ssafy.b209.report.service;

import com.openhtmltopdf.outputdevice.helper.BaseRendererBuilder;
import com.openhtmltopdf.pdfboxout.PdfRendererBuilder;
import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
import com.ssafy.b209.report.exception.ReportExportErrorCode;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 보호자에게 공개 가능한 리포트 상세 DTO를 문서 서식의 한글 PDF로 렌더링한다.
 *
 * <p>입력 DTO 자체가 보호자 안전 필드를 선별하므로 AI 내부 지표나 전문가 전용 관찰값을 별도로 조회하지 않는다.
 *
 * <h2>이 클래스가 하는 일</h2>
 *
 * <p>세 가지뿐이다 — 문서에 실을 <b>그림을 미리 읽고</b>, {@link ReportPdfTemplate}에게 <b>XHTML을 받아</b>,
 * openhtmltopdf로 <b>PDF를 굽는다</b>. 서식·문구·페이지 분할 규칙은 전부 템플릿에 있다.
 *
 * <p>예전에는 PDFBox로 좌표를 직접 계산해 카드를 그렸다({@code ReportPdfWriter}). 카드가 장 경계에서 잘리지 않게 하려면 남은 높이를 매번 손으로
 * 재야 했고, 표지·요약 배치를 바꿀 때마다 그 계산이 따라 붙었다. 지금은 CSS가 그 일을 한다(ADR-0003, S15P11B209-968).
 *
 * <h2>그림을 왜 여기서 읽는가</h2>
 *
 * <p>리포트 응답은 그림을 <b>인증이 필요한 상대 URL</b>로만 노출한다(계약). 서버가 그 URL을 HTTP로 다시 부르면 스스로 토큰을 만들어야 하고 자기 호출이
 * 실패 지점이 된다. 그래서 URL에서 식별자만 되읽어 {@link ReportAssetResolver}로 저장소에서 직접 읽는다(S15P11B209-966).
 *
 * <p>그림을 못 읽으면 그림 없이 문서를 만든다. 그림 한 장 때문에 내보내기 전체가 실패하면 보호자는 아무것도 받지 못한다.
 *
 * <h2>결과를 저장하지 않는다</h2>
 *
 * <p>요청마다 새로 만든다. 이미지를 포함한 5장 이상 문서가 약 100ms 에 나오고(S15P11B209-967 실측), 다운로드는 보호자가 직접 누르는 동기 동작이라
 * 체감되지 않는다. 저장하면 리포트 버전이 오르거나 공개 범위가 바뀔 때 <b>무효화 책임</b>이 생기고, 놓치면 보호자가 낡은 문서를 받는다 — 100ms 보다 나쁘다.
 * {@code ReportPdfStatus} 를 살릴 조건은 ADR-0003 에 적어 두었다.
 */
@Component
public class ReportPdfRenderer {

  private static final Logger log = LoggerFactory.getLogger(ReportPdfRenderer.class);

  private static final String REGULAR_FONT = "/fonts/NanumSquareNeo-Regular.ttf";
  private static final String BOLD_FONT = "/fonts/NanumSquareNeo-Bold.ttf";

  /** CSS {@code font-weight} 값이다. 굵은 글씨가 없으면 제목과 본문의 층이 사라진다. */
  private static final int REGULAR_WEIGHT = 400;

  private static final int BOLD_WEIGHT = 700;

  private final ReportAssetResolver assetResolver;
  private final DrawingAssetFileUrlFactory fileUrlFactory;

  /**
   * 리포트 PDF 렌더러를 구성한다.
   *
   * @param assetResolver 문서에 실을 그림을 저장소에서 읽는 경계
   * @param fileUrlFactory 그림 URL과 식별자를 서로 옮기는 경계
   */
  public ReportPdfRenderer(
      ReportAssetResolver assetResolver, DrawingAssetFileUrlFactory fileUrlFactory) {
    this.assetResolver = assetResolver;
    this.fileUrlFactory = fileUrlFactory;
  }

  /**
   * 보호자용 리포트 상세를 PDF 바이트로 변환한다.
   *
   * <p>렌더링 실패는 <b>종류를 가리지 않고</b> {@link ReportExportErrorCode#REPORT_EXPORT_FAILED}로 분류한다. 이전에는
   * {@code IOException}과 {@code IllegalArgumentException}만 감싸서, 그 밖의 예외가 전역 핸들러까지 올라가 {@code
   * COMMON_500_001}("서버 내부 오류가 발생했습니다.")로 응답됐다. 그 코드로는 클라이언트도 로그 독자도 <b>무엇이 실패했는지 알 수 없다</b> — 배포
   * 서버에서 PDF 다운로드가 그렇게 실패했고(S15P11B209-860) 원인 추적이 서버 로그 확보 없이는 불가능했다. 같은 실패 분류 소실이
   * S15P11B209-815에서도 리포트 생성을 전면 실패시켰다.
   *
   * @param report 보호자 권한과 안전 필드 검증을 마친 리포트
   * @return PDF 파일 바이트
   * @throws BusinessException 폰트 또는 PDF 문서를 생성할 수 없는 경우
   */
  public byte[] render(ReportDetailResponse report) {
    try {
      String html = new ReportPdfTemplate(report, resolveImages(report)).build();
      return renderHtml(html);
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | RuntimeException exception) {
      // 근본 원인을 로그에 남긴다. 예외 타입·메시지만으로는 다음 발생 때도 같은 조사를 반복해야 한다.
      log.error(
          "리포트 PDF 렌더링에 실패했습니다. reportId={}, exceptionType={}, message={}",
          report == null ? null : report.reportId(),
          exception.getClass().getName(),
          exception.getMessage(),
          exception);
      throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_FAILED, exception);
    }
  }

  private byte[] renderHtml(String html) throws IOException {
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    PdfRendererBuilder builder = new PdfRendererBuilder();
    // 빠른 렌더 경로다. 느린 경로는 우리가 쓰지 않는 SVG·MathML 확장을 위한 것이다.
    builder.useFastMode();
    useFont(builder, REGULAR_FONT, REGULAR_WEIGHT);
    useFont(builder, BOLD_FONT, BOLD_WEIGHT);
    // 기준 URL을 주지 않는다. 문서는 이미지·폰트를 모두 품고 있어 바깥을 볼 이유가 없고,
    //   준다면 문서 내용이 서버에서 파일을 읽는 경로가 된다.
    builder.withHtmlContent(html, null);
    builder.toStream(output);
    builder.run();
    return output.toByteArray();
  }

  /**
   * 폰트를 문서에 임베드한다.
   *
   * <p>운영 이미지에는 한글 폰트가 없다. OS 폰트를 찾게 두면 로컬에서는 나오고 배포에서는 글자가 빠진다. 리소스에서 직접 읽어 항상 같은 글꼴을 쓴다.
   */
  private void useFont(PdfRendererBuilder builder, String resource, int weight) {
    builder.useFont(
        () -> {
          InputStream stream = ReportPdfRenderer.class.getResourceAsStream(resource);
          if (stream == null) {
            log.error("리포트 PDF 폰트 리소스를 찾을 수 없습니다. resource={}", resource);
            throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_FAILED);
          }
          return stream;
        },
        ReportPdfTemplate.FONT_FAMILY,
        weight,
        BaseRendererBuilder.FontStyle.NORMAL,
        true);
  }

  /**
   * 문서에 실을 그림을 미리 읽어 URL로 찾을 수 있게 모은다.
   *
   * <p>같은 URL이 여러 번 나와도 한 번만 읽는다.
   *
   * @param report 리포트 상세
   * @return 그림 URL로 찾는 이미지이며 실을 그림이 없으면 빈 Map
   */
  private Map<String, ReportImageAsset> resolveImages(ReportDetailResponse report) {
    if (report == null) return Map.of();
    List<String> urls = new ArrayList<>();
    if (report.drawing() != null) {
      urls.add(report.drawing().finalImageUrl());
    }
    if (report.subjectReports() != null) {
      for (ReportSubjectResponse subject : report.subjectReports()) {
        urls.add(subject.imageUrl());
      }
    }
    Map<String, ReportImageAsset> images = new LinkedHashMap<>();
    for (String url : urls) {
      if (url == null || url.isBlank() || images.containsKey(url)) continue;
      resolve(url).ifPresent(asset -> images.put(url, asset));
    }
    return images;
  }

  private Optional<ReportImageAsset> resolve(String fileUrl) {
    Optional<Long> assetId = fileUrlFactory.parseAssetId(fileUrl);
    if (assetId.isEmpty()) {
      // URL 형식이 바뀌었거나 다른 곳에서 만든 URL이다. 그림만 빼고 문서는 만든다.
      log.warn("리포트 그림 URL에서 식별자를 읽지 못했습니다. fileUrl={}", fileUrl);
      return Optional.empty();
    }
    return assetResolver.resolveDrawingImage(assetId.get());
  }
}
