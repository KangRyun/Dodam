package com.ssafy.b209.user.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DataExportJobTest {

  @Test
  void startsInPendingStateAtTheRequestTime() {
    LocalDateTime requestedAt = LocalDateTime.of(2026, 7, 31, 10, 25, 3);

    DataExportJob job = DataExportJob.requested(51L, requestedAt);

    assertThat(job.getUserId()).isEqualTo(51L);
    assertThat(job.getExportStatus()).isEqualTo(DataExportStatus.PENDING);
    assertThat(job.getCreatedAt()).isEqualTo(requestedAt);
  }
}
