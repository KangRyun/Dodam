package com.ssafy.b209.user.dto.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.user.domain.DataExportStatus;
import java.lang.reflect.RecordComponent;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DataExportJobResponseTest {

  @Test
  void exposesOnlyThePersistedPublicJobFields() {
    assertThat(DataExportJobResponse.class.getRecordComponents())
        .extracting(RecordComponent::getName)
        .containsExactly("dataExportJobId", "exportStatus", "requestedAt");

    DataExportJobResponse response =
        new DataExportJobResponse(
            901L, DataExportStatus.PENDING, LocalDateTime.of(2026, 7, 31, 10, 25, 3));

    assertThat(response.exportStatus()).isEqualTo(DataExportStatus.PENDING);
  }
}
