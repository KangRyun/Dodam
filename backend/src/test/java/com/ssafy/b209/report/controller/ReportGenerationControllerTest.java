package com.ssafy.b209.report.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportGenerationStatusResponse;
import com.ssafy.b209.report.service.ReportGenerationService;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ReportGenerationControllerTest {

  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ReportGenerationService service;

  private ReportGenerationController controller;

  @BeforeEach
  void setUp() {
    controller = new ReportGenerationController(guardianResolver, service);
  }

  @Test
  void returnsGenerationStatusForResolvedGuardian() {
    ReportGenerationStatusResponse status = status(900L, ReportStatus.FAILED, true);
    when(guardianResolver.resolve("Bearer token", null)).thenReturn(41L);
    when(service.getStatus(41L, 900L)).thenReturn(status);

    ResponseEntity<ApiResponse<ReportGenerationStatusResponse>> response =
        controller.getGenerationStatus(900L, "Bearer token", null);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().data()).isSameAs(status);
  }

  @Test
  void acceptsRegenerationAndProvidesPollingLocation() {
    ReportGenerationStatusResponse status = status(901L, ReportStatus.GENERATING, false);
    when(guardianResolver.resolve(null, "41")).thenReturn(41L);
    when(service.regenerate(41L, 900L, "report-regeneration-key")).thenReturn(status);

    ResponseEntity<ApiResponse<ReportGenerationStatusResponse>> response =
        controller.regenerate(900L, "report-regeneration-key", null, "41");

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
    assertThat(response.getHeaders().getLocation())
        .hasToString("/api/v1/reports/901/generation-status");
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().data()).isSameAs(status);
  }

  private ReportGenerationStatusResponse status(
      Long reportId, ReportStatus reportStatus, boolean retryable) {
    return new ReportGenerationStatusResponse(
        reportId,
        100L,
        reportId == 900L ? 701L : 702L,
        reportId == 900L ? 1 : 2,
        reportStatus,
        retryable,
        retryable ? "OBSERVATION_GENERATION_FAILED" : null,
        LocalDateTime.of(2026, 7, 23, 10, 30),
        LocalDateTime.of(2026, 7, 23, 10, 31),
        retryable ? LocalDateTime.of(2026, 7, 23, 10, 31) : null);
  }
}
