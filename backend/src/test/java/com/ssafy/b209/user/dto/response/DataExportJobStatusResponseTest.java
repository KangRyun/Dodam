package com.ssafy.b209.user.dto.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.user.domain.DataExportStatus;
import java.lang.reflect.RecordComponent;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DataExportJobStatusResponseTest {

  @Test
  void exposesOnlyTheStatusQueryFields() {
    assertThat(DataExportJobStatusResponse.class.getRecordComponents())
        .extracting(RecordComponent::getName)
        .containsExactly(
            "dataExportJobId",
            "exportStatus",
            "requestedAt",
            "completedAt",
            "expiresAt",
            "failureCode");

    DataExportJobStatusResponse response =
        new DataExportJobStatusResponse(
            901L,
            DataExportStatus.PROCESSING,
            LocalDateTime.of(2026, 7, 31, 10, 25, 3),
            null,
            null,
            null);

    assertThat(response.exportStatus()).isEqualTo(DataExportStatus.PROCESSING);
  }
}
