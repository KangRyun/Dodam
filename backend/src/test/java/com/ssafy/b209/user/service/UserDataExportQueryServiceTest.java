package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.domain.DataExportJob;
import com.ssafy.b209.user.domain.DataExportStatus;
import com.ssafy.b209.user.dto.response.DataExportJobStatusResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import com.ssafy.b209.user.repository.DataExportJobRepository;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class UserDataExportQueryServiceTest {

  @Mock private DataExportJobRepository dataExportJobRepository;

  private UserDataExportQueryService service;

  @BeforeEach
  void setUp() {
    service = new UserDataExportQueryService(dataExportJobRepository);
  }

  @Test
  void returnsOnlyTheOwnersCurrentExportJobStatus() {
    DataExportJob job = DataExportJob.requested(51L, LocalDateTime.of(2026, 7, 31, 10, 25, 3));
    ReflectionTestUtils.setField(job, "id", 901L);
    ReflectionTestUtils.setField(job, "exportStatus", DataExportStatus.FAILED);
    ReflectionTestUtils.setField(job, "completedAt", LocalDateTime.of(2026, 7, 31, 10, 30, 3));
    ReflectionTestUtils.setField(job, "expiresAt", LocalDateTime.of(2026, 8, 1, 10, 30, 3));
    ReflectionTestUtils.setField(job, "errorCode", "EXPORT_STORAGE_ERROR");
    given(dataExportJobRepository.findByIdAndUserId(901L, 51L)).willReturn(Optional.of(job));

    DataExportJobStatusResponse response = service.get(51L, 901L);

    assertThat(response)
        .isEqualTo(
            new DataExportJobStatusResponse(
                901L,
                DataExportStatus.FAILED,
                LocalDateTime.of(2026, 7, 31, 10, 25, 3),
                LocalDateTime.of(2026, 7, 31, 10, 30, 3),
                LocalDateTime.of(2026, 8, 1, 10, 30, 3),
                "EXPORT_STORAGE_ERROR"));
  }

  @Test
  void hidesUnknownAndOtherUsersJobsWithTheSameNotFoundCode() {
    given(dataExportJobRepository.findByIdAndUserId(902L, 51L)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.get(51L, 902L))
        .isInstanceOf(BusinessException.class)
        .extracting(error -> ((BusinessException) error).getErrorCode())
        .isEqualTo(UserErrorCode.DATA_EXPORT_JOB_NOT_FOUND);
  }
}
