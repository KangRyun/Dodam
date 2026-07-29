package com.ssafy.b209.report.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.report.dto.ReportExportResponse;
import com.ssafy.b209.report.service.ReportExportService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
class ReportExportControllerContractTest {

  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ReportExportService reportExportService;

  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    mockMvc =
        MockMvcBuilders.standaloneSetup(
                new ReportExportController(guardianResolver, reportExportService))
            .build();
  }

  @Test
  void acceptsReportExportRequest() throws Exception {
    org.mockito.Mockito.when(guardianResolver.resolve("Bearer token", null)).thenReturn(10L);
    org.mockito.Mockito.when(reportExportService.requestExport(10L, 500L, "report-export-500"))
        .thenReturn(
            new ReportExportResponse(
                500L, 500L, "COMPLETED", "/api/v1/reports/500/exports/500/file"));

    mockMvc
        .perform(
            post("/api/v1/reports/{reportId}/exports", 500L)
                .header("Authorization", "Bearer token")
                .header("Idempotency-Key", "report-export-500"))
        .andExpect(status().isAccepted())
        .andExpect(header().string("Location", "/api/v1/reports/500/exports/500"))
        .andExpect(jsonPath("$.data.status").value("COMPLETED"));
  }
}
