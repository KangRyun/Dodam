package com.ssafy.b209.report.controller;

import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.report.dto.ReportPdfFile;
import com.ssafy.b209.report.service.ReportExportService;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * PDF 다운로드를 <b>Spring MVC 응답 변환 경로까지</b> 검증한다 (S15P11B209-860).
 *
 * <p>기존 {@code ReportExportControllerContractTest} 는 POST(접수)만 덮고 있었고, 그 빈 구간에 결함이 있었다. 앱은 {@link
 * com.ssafy.b209.report.service.ReportExportService} 가 PDF 를 정상 생성해도 다운로드가 {@code COMMON_500_001} 로
 * 실패했다 — 앱이 모든 요청에 {@code Accept: application/json} 을 붙이는데 Endpoint 가 {@code produces =
 * application/pdf} 를 선언해 콘텐츠 협상에서 거부됐고, 그 실패는 컨트롤러 메서드 밖에서 나 서비스의 예외 분류를 지나쳤다.
 *
 * <p>그래서 서비스·렌더러 단위 테스트로는 절대 잡히지 않았다. 여기서 <b>클라이언트가 보내는 실제 {@code Accept}</b> 를 재현한다.
 */
@WebMvcTest(ReportExportController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class ReportExportDownloadControllerTest {

  private static final byte[] PDF_BYTES = "%PDF-1.6 fake".getBytes(StandardCharsets.UTF_8);

  @Autowired private MockMvc mockMvc;
  @MockitoBean private GuardianUserResolver guardianResolver;
  @MockitoBean private ReportExportService reportExportService;

  @Test
  void downloadsPdfWhenClientAsksForJsonLikeTheApp() throws Exception {
    // 앱의 ApiClient 가 붙이는 헤더 그대로다. 이 조합이 실기기에서 500을 만들었다.
    givenPdf();

    mockMvc
        .perform(
            get("/api/v1/reports/{reportId}/exports/{exportId}/file", 77L, 77L)
                .header("Authorization", "Bearer token")
                .header("Accept", MediaType.APPLICATION_JSON_VALUE))
        .andExpect(status().isOk())
        .andExpect(content().contentType(MediaType.APPLICATION_PDF))
        .andExpect(content().bytes(PDF_BYTES));
  }

  @Test
  void downloadsPdfWhenClientAsksForPdf() throws Exception {
    givenPdf();

    mockMvc
        .perform(
            get("/api/v1/reports/{reportId}/exports/{exportId}/file", 77L, 77L)
                .header("Authorization", "Bearer token")
                .header("Accept", MediaType.APPLICATION_PDF_VALUE))
        .andExpect(status().isOk())
        .andExpect(content().contentType(MediaType.APPLICATION_PDF));
  }

  @Test
  void sendsAttachmentDispositionWithFileName() throws Exception {
    givenPdf();

    mockMvc
        .perform(
            get("/api/v1/reports/{reportId}/exports/{exportId}/file", 77L, 77L)
                .header("Authorization", "Bearer token"))
        .andExpect(status().isOk())
        .andExpect(
            header()
                .string("Content-Disposition", org.hamcrest.Matchers.containsString("attachment")))
        .andExpect(
            header()
                .string(
                    "Content-Disposition",
                    org.hamcrest.Matchers.containsString("dodam-report-77.pdf")));
  }

  private void givenPdf() {
    given(guardianResolver.resolve("Bearer token", null)).willReturn(10L);
    given(reportExportService.download(10L, 77L, 77L))
        .willReturn(new ReportPdfFile("dodam-report-77.pdf", PDF_BYTES));
  }
}
