package com.ssafy.b209.expert.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertCredential;
import com.ssafy.b209.expert.domain.ExpertCredentialFile;
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertCredentialRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.credential.CredentialFileStorage;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

class ExpertCredentialManagementServiceTest {

  @AfterEach
  void clearSynchronization() {
    if (TransactionSynchronizationManager.isSynchronizationActive()) {
      TransactionSynchronizationManager.clearSynchronization();
    }
  }

  @Test
  void listsOnlyCurrentExpertsCredentialsInNewestOrder() {
    Fixture fixture = new Fixture();
    ExpertCredential credential = fixture.credential(31L, ExpertVerificationStatus.PENDING);
    given(fixture.resolver.requireUserId()).willReturn(7L);
    given(fixture.repository.findAllOwnedByUserId(7L)).willReturn(List.of(credential));

    var result = fixture.service.listMine();

    assertThat(result)
        .singleElement()
        .satisfies(item -> assertThat(item.credentialId()).isEqualTo(31L));
  }

  @Test
  void deletesPendingCredentialFileAfterDatabaseCommit() {
    Fixture fixture = new Fixture();
    ExpertCredential credential = fixture.credential(31L, ExpertVerificationStatus.PENDING);
    given(fixture.resolver.requireUserId()).willReturn(7L);
    given(fixture.repository.findOwnedById(31L, 7L)).willReturn(Optional.of(credential));
    TransactionSynchronizationManager.initSynchronization();

    fixture.service.deleteMine(31L);

    verify(fixture.repository).delete(credential);
    verify(fixture.storage, never()).delete("2026/08/03/file.pdf");
    TransactionSynchronizationManager.getSynchronizations()
        .forEach(TransactionSynchronization::afterCommit);
    verify(fixture.storage).delete("2026/08/03/file.pdf");
  }

  @Test
  void rejectsDeletingCredentialThatAlreadyHasReviewHistory() {
    Fixture fixture = new Fixture();
    ExpertCredential credential = fixture.credential(31L, ExpertVerificationStatus.VERIFIED);
    given(fixture.resolver.requireUserId()).willReturn(7L);
    given(fixture.repository.findOwnedById(31L, 7L)).willReturn(Optional.of(credential));

    assertThatThrownBy(() -> fixture.service.deleteMine(31L))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.CREDENTIAL_DELETE_NOT_ALLOWED));
    verify(fixture.repository, never()).delete(credential);
  }

  @Test
  void hidesWhetherCredentialBelongsToAnotherExpert() {
    Fixture fixture = new Fixture();
    given(fixture.resolver.requireUserId()).willReturn(7L);
    given(fixture.repository.findOwnedById(31L, 7L)).willReturn(Optional.empty());

    assertThatThrownBy(() -> fixture.service.deleteMine(31L))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.CREDENTIAL_NOT_FOUND));
  }

  private static class Fixture {
    private final CurrentAuthenticatedUserResolver resolver =
        mock(CurrentAuthenticatedUserResolver.class);
    private final ExpertCredentialRepository repository = mock(ExpertCredentialRepository.class);
    private final CredentialFileStorage storage = mock(CredentialFileStorage.class);
    private final ExpertCredentialManagementService service =
        new ExpertCredentialManagementService(resolver, repository, storage);

    private ExpertCredential credential(Long id, ExpertVerificationStatus status) {
      ExpertCredential credential = mock(ExpertCredential.class);
      ExpertCredentialFile file = mock(ExpertCredentialFile.class);
      given(credential.getId()).willReturn(id);
      given(credential.getCredentialType()).willReturn("ART_THERAPIST");
      given(credential.getCredentialName()).willReturn("미술심리상담사");
      given(credential.getIssuer()).willReturn("한국상담협회");
      given(credential.getVerificationStatus()).willReturn(status);
      given(credential.getCreatedAt()).willReturn(LocalDateTime.parse("2026-08-03T00:00:00"));
      given(credential.getFiles()).willReturn(List.of(file));
      given(file.getFileName()).willReturn("license.pdf");
      given(file.getMimeType()).willReturn("application/pdf");
      given(file.getFileSizeBytes()).willReturn(9L);
      given(file.getStorageKey()).willReturn("2026/08/03/file.pdf");
      return credential;
    }
  }
}
