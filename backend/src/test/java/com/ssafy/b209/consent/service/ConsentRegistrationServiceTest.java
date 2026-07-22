package com.ssafy.b209.consent.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentRecord;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.domain.ConsentTerm;
import com.ssafy.b209.consent.dto.request.ConsentAgreementRequest;
import com.ssafy.b209.consent.dto.request.CreateConsentRequest;
import com.ssafy.b209.consent.dto.response.ConsentRegistrationResponse;
import com.ssafy.b209.consent.exception.ConsentErrorCode;
import com.ssafy.b209.consent.repository.ConsentAuthorizationRepository;
import com.ssafy.b209.consent.repository.ConsentRecordRepository;
import com.ssafy.b209.consent.repository.ConsentTermRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ConsentRegistrationServiceTest {

  private static final LocalDateTime NOW = LocalDateTime.of(2026, 7, 23, 0, 0);

  @Mock private ConsentTermRepository termRepository;
  @Mock private ConsentRecordRepository recordRepository;
  @Mock private ConsentAuthorizationRepository authorizationRepository;

  private ConsentRegistrationService service;

  @BeforeEach
  void setUp() {
    service =
        new ConsentRegistrationService(
            termRepository,
            recordRepository,
            authorizationRepository,
            new ConsentSubjectHasher(),
            Clock.fixed(Instant.parse("2026-07-23T00:00:00Z"), ZoneOffset.UTC));
  }

  @Test
  @SuppressWarnings("unchecked")
  void appendsUserAndChildConsentRecordsAfterRequiredConsentValidation() {
    ConsentTerm userRequired = term(1L, ConsentTargetScope.USER, true, true);
    ConsentTerm childRequired = term(2L, ConsentTargetScope.CHILD, true, true);
    ConsentTerm childOptional = term(3L, ConsentTargetScope.CHILD, false, true);
    CreateConsentRequest request =
        request(
            7L,
            agreement(1L, ConsentAction.AGREE),
            agreement(2L, ConsentAction.AGREE),
            agreement(3L, ConsentAction.WITHDRAW));
    when(authorizationRepository.hasGuardianChildRelation(41L, 7L)).thenReturn(true);
    when(termRepository.findAllById(org.mockito.ArgumentMatchers.anySet()))
        .thenReturn(List.of(userRequired, childRequired, childOptional));
    when(termRepository.findAllByActiveTrue())
        .thenReturn(List.of(userRequired, childRequired, childOptional));

    ConsentRegistrationResponse response =
        service.register(41L, request, "127.0.0.1", "test-agent");

    assertThat(response.childId()).isEqualTo(7L);
    assertThat(response.recordedCount()).isEqualTo(3);
    assertThat(response.requiredConsentsSatisfied()).isTrue();
    assertThat(response.recordedAt()).isEqualTo(NOW);
    ArgumentCaptor<List<ConsentRecord>> captor = ArgumentCaptor.forClass(List.class);
    verify(recordRepository).saveAll(captor.capture());
    assertThat(captor.getValue()).hasSize(3);
    assertThat(ReflectionTestUtils.getField(captor.getValue().get(0), "actorUserId"))
        .isEqualTo(41L);
    assertThat(
            captor.getValue().stream()
                .map(record -> ReflectionTestUtils.getField(record, "subjectReferenceHash")))
        .allSatisfy(hash -> assertThat(hash.toString()).hasSize(64));
  }

  @Test
  void rejectsRegistrationWhenRequiredAgreementIsMissing() {
    ConsentTerm required = term(1L, ConsentTargetScope.USER, true, true);
    ConsentTerm optional = term(2L, ConsentTargetScope.USER, false, true);
    CreateConsentRequest request = request(null, agreement(2L, ConsentAction.AGREE));
    when(termRepository.findAllById(org.mockito.ArgumentMatchers.anySet()))
        .thenReturn(List.of(optional));
    when(termRepository.findAllByActiveTrue()).thenReturn(List.of(required, optional));

    assertThatThrownBy(() -> service.register(41L, request, null, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConsentErrorCode.REQUIRED_CONSENT_MISSING));

    verify(recordRepository, never()).saveAll(anyList());
  }

  @Test
  void rejectsChildConsentFromUnlinkedUserBeforeWriting() {
    CreateConsentRequest request = request(7L, agreement(2L, ConsentAction.AGREE));
    when(authorizationRepository.hasGuardianChildRelation(41L, 7L)).thenReturn(false);

    assertThatThrownBy(() -> service.register(41L, request, null, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConsentErrorCode.CONSENT_ACTOR_NOT_GUARDIAN));

    verify(recordRepository, never()).saveAll(anyList());
  }

  @Test
  void rejectsInactiveReferencedTerm() {
    ConsentTerm inactive = term(1L, ConsentTargetScope.USER, true, false);
    CreateConsentRequest request = request(null, agreement(1L, ConsentAction.AGREE));
    when(termRepository.findAllById(org.mockito.ArgumentMatchers.anySet()))
        .thenReturn(List.of(inactive));

    assertThatThrownBy(() -> service.register(41L, request, null, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConsentErrorCode.TERM_VERSION_INACTIVE));
  }

  private ConsentTerm term(Long id, ConsentTargetScope scope, boolean required, boolean active) {
    ConsentTerm term =
        ConsentTerm.define(
            scope.name() + "_TERM_" + id,
            scope,
            required,
            "1.0",
            "약관",
            null,
            NOW.minusDays(1),
            active,
            NOW.minusDays(2));
    ReflectionTestUtils.setField(term, "id", id);
    return term;
  }

  private ConsentAgreementRequest agreement(Long termId, ConsentAction action) {
    return new ConsentAgreementRequest(termId, action);
  }

  private CreateConsentRequest request(Long childId, ConsentAgreementRequest... agreements) {
    return new CreateConsentRequest(childId, List.of(agreements));
  }
}
