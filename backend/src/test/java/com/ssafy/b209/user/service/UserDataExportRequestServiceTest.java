package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.user.domain.DataExportJob;
import com.ssafy.b209.user.domain.DataExportStatus;
import com.ssafy.b209.user.dto.response.DataExportJobResponse;
import com.ssafy.b209.user.repository.DataExportJobRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class UserDataExportRequestServiceTest {

  @Mock private DataExportJobRepository dataExportJobRepository;

  @Test
  void savesAPendingJobForTheAuthenticatedUserAndReturnsItsPublicState() {
    Clock clock = Clock.fixed(Instant.parse("2026-07-31T10:25:03Z"), ZoneOffset.UTC);
    UserDataExportRequestService service =
        new UserDataExportRequestService(dataExportJobRepository, clock);
    given(dataExportJobRepository.save(any(DataExportJob.class)))
        .willAnswer(
            invocation -> {
              DataExportJob job = invocation.getArgument(0);
              ReflectionTestUtils.setField(job, "id", 901L);
              return job;
            });

    DataExportJobResponse response = service.request(51L);

    ArgumentCaptor<DataExportJob> jobCaptor = ArgumentCaptor.forClass(DataExportJob.class);
    verify(dataExportJobRepository).save(jobCaptor.capture());
    assertThat(jobCaptor.getValue().getUserId()).isEqualTo(51L);
    assertThat(jobCaptor.getValue().getExportStatus()).isEqualTo(DataExportStatus.PENDING);
    assertThat(response)
        .isEqualTo(
            new DataExportJobResponse(
                901L,
                DataExportStatus.PENDING,
                java.time.LocalDateTime.of(2026, 7, 31, 10, 25, 3)));
  }
}
