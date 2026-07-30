package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.user.dto.response.DataRetentionPolicyResponse;
import com.ssafy.b209.user.repository.UserDataRetentionSettingsProjection;
import com.ssafy.b209.user.repository.UserDataRetentionSettingsRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserDataRetentionPolicyReaderTest {

  @Mock private UserDataRetentionSettingsRepository dataRetentionSettingsRepository;

  @Test
  void returnsStoredRetentionPolicyWhenSettingsRowExists() {
    given(dataRetentionSettingsRepository.findByUserId(51L))
        .willReturn(Optional.of(projection(365, 14)));

    DataRetentionPolicyResponse response = reader().read(51L);

    assertThat(response.retentionDays()).isEqualTo(365);
    assertThat(response.noticeDaysBefore()).isEqualTo(14);
    assertThat(response.policyStatus()).isEqualTo("PROVISIONAL");
  }

  @Test
  void returnsColumnDefaultsWhenSettingsRowIsMissing() {
    given(dataRetentionSettingsRepository.findByUserId(51L)).willReturn(Optional.empty());

    DataRetentionPolicyResponse response = reader().read(51L);

    assertThat(response).isEqualTo(DataRetentionPolicyResponse.defaults());
    assertThat(response.retentionDays()).isEqualTo(180);
    assertThat(response.noticeDaysBefore()).isEqualTo(30);
    assertThat(response.policyStatus()).isEqualTo("PROVISIONAL");
  }

  @Test
  void marksStoredPolicyAsProvisionalBecauseTeamHasNotConfirmedTheNumbers() {
    given(dataRetentionSettingsRepository.findByUserId(51L))
        .willReturn(Optional.of(projection(30, 7)));

    assertThat(reader().read(51L).policyStatus())
        .isEqualTo(DataRetentionPolicyResponse.PROVISIONAL);
  }

  private UserDataRetentionPolicyReader reader() {
    return new UserDataRetentionPolicyReader(dataRetentionSettingsRepository);
  }

  private static UserDataRetentionSettingsProjection projection(
      int retentionDays, int noticeDaysBefore) {
    return new UserDataRetentionSettingsProjection() {
      @Override
      public int getRetentionDays() {
        return retentionDays;
      }

      @Override
      public int getNoticeDaysBefore() {
        return noticeDaysBefore;
      }
    };
  }
}
