package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.user.dto.request.DataRetentionPolicyUpdateRequest;
import com.ssafy.b209.user.dto.response.DataRetentionPolicyResponse;
import com.ssafy.b209.user.repository.UserDataRetentionSettingsRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserDataRetentionPolicyUpdateServiceTest {

  @Mock private UserDataRetentionSettingsRepository dataRetentionSettingsRepository;
  @Mock private UserDataRetentionPolicyReader dataRetentionPolicyReader;
  @InjectMocks private UserDataRetentionPolicyUpdateService updateService;

  @Test
  void upsertsTheFullPolicyAndReturnsTheSharedReadResponse() {
    DataRetentionPolicyResponse expected = DataRetentionPolicyResponse.provisional(365, 14);
    given(dataRetentionPolicyReader.read(51L)).willReturn(expected);

    DataRetentionPolicyResponse actual =
        updateService.update(51L, new DataRetentionPolicyUpdateRequest(365, 14));

    verify(dataRetentionSettingsRepository).upsert(51L, 365, 14);
    verify(dataRetentionPolicyReader).read(51L);
    assertThat(actual).isSameAs(expected);
  }
}
