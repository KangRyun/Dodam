package com.ssafy.b209.expert.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertCredential;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.dto.request.UploadExpertCredentialRequest;
import com.ssafy.b209.expert.repository.ExpertCredentialRepository;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.storage.credential.CredentialFileStorage;
import com.ssafy.b209.storage.credential.StoreCredentialFileCommand;
import com.ssafy.b209.storage.credential.StoredCredentialFile;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

class ExpertCredentialUploadServiceTest {

  @AfterEach
  void clearSynchronization() {
    if (TransactionSynchronizationManager.isSynchronizationActive()) {
      TransactionSynchronizationManager.clearSynchronization();
    }
  }

  @Test
  void deletesStoredFileWhenDatabaseTransactionRollsBack() {
    CurrentAuthenticatedUserResolver resolver = mock(CurrentAuthenticatedUserResolver.class);
    UserRepository userRepository = mock(UserRepository.class);
    ExpertProfileRepository profileRepository = mock(ExpertProfileRepository.class);
    ExpertCredentialRepository credentialRepository = mock(ExpertCredentialRepository.class);
    CredentialFileStorage storage = mock(CredentialFileStorage.class);
    User user = mock(User.class);
    ExpertProfile profile = mock(ExpertProfile.class);
    StoreCredentialFileCommand command =
        new StoreCredentialFileCommand("%PDF-1.7\n".getBytes(), "application/pdf", "license.pdf");
    UploadExpertCredentialRequest request =
        new UploadExpertCredentialRequest("ART_THERAPIST", "미술심리상담사", "한국상담협회", null, null);

    given(resolver.requireUserId()).willReturn(1L);
    given(userRepository.findById(1L)).willReturn(Optional.of(user));
    given(user.getRole()).willReturn(UserRole.EXPERT);
    given(user.getAccountStatus()).willReturn(AccountStatus.ACTIVE);
    given(user.isOnboardingCompleted()).willReturn(true);
    given(profileRepository.findDetailByUserId(1L)).willReturn(Optional.of(profile));
    given(storage.store(command))
        .willReturn(
            new StoredCredentialFile("2026/08/03/file.pdf", "a".repeat(64), "application/pdf", 9L));
    given(
            credentialRepository.saveAndFlush(
                org.mockito.ArgumentMatchers.any(ExpertCredential.class)))
        .willThrow(new IllegalStateException("database failure"));
    ExpertCredentialUploadService service =
        new ExpertCredentialUploadService(
            resolver,
            userRepository,
            profileRepository,
            credentialRepository,
            storage,
            Clock.fixed(Instant.parse("2026-08-03T00:00:00Z"), ZoneOffset.UTC));
    TransactionSynchronizationManager.initSynchronization();

    assertThatThrownBy(() -> service.upload(command, request))
        .isInstanceOf(IllegalStateException.class);
    TransactionSynchronizationManager.getSynchronizations()
        .forEach(
            synchronization ->
                synchronization.afterCompletion(TransactionSynchronization.STATUS_ROLLED_BACK));

    verify(storage).delete("2026/08/03/file.pdf");
  }
}
