package com.ssafy.b209.screening.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.screening.domain.ChildScreeningRecord;
import com.ssafy.b209.screening.domain.ScreeningRespondent;
import com.ssafy.b209.screening.domain.ScreeningSourceAuthorityType;
import com.ssafy.b209.screening.dto.request.RegisterScreeningRecordRequest;
import com.ssafy.b209.screening.exception.ScreeningRecordErrorCode;
import com.ssafy.b209.screening.registry.ScreeningInstrumentRegistry;
import com.ssafy.b209.screening.repository.ChildScreeningRecordDomainRepository;
import com.ssafy.b209.screening.repository.ChildScreeningRecordRepository;
import com.ssafy.b209.screening.repository.ChildScreeningReferralOptionRepository;
import com.ssafy.b209.screening.repository.ClinicalConsentRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/**
 * 보호자가 옮겨 적는 검사 기록이 지켜야 하는 것을 고정한다.
 *
 * <p>여기서 막는 실패는 셋이다 — 임의의 검사명이 아동 기록에 남는 것, 동의 없이 의료 기록이 저장되는 것, 그리고 <strong>검증되지 않은 입력이 공식 결과로
 * 올라가는 것.</strong>
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ScreeningRecordCommandServiceTest {

  private static final Long GUARDIAN_ID = 7L;
  private static final Long CHILD_ID = 42L;
  private static final Long CONSENT_ID = 901L;

  @Mock private GuardianResourceAccessRepository guardianAccessRepository;
  @Mock private ChildRepository childRepository;
  @Mock private ChildScreeningRecordRepository recordRepository;
  @Mock private ChildScreeningRecordDomainRepository domainRepository;
  @Mock private ChildScreeningReferralOptionRepository referralOptionRepository;
  @Mock private ClinicalConsentRepository clinicalConsentRepository;
  @Mock private Child child;

  private ScreeningRecordCommandService service;

  @BeforeEach
  void setUp() {
    service =
        new ScreeningRecordCommandService(
            guardianAccessRepository,
            childRepository,
            recordRepository,
            domainRepository,
            referralOptionRepository,
            clinicalConsentRepository,
            new ObjectMapper().findAndRegisterModules(),
            Clock.fixed(Instant.parse("2026-08-08T00:00:00Z"), ZoneOffset.UTC));
    when(guardianAccessRepository.hasChildAccess(GUARDIAN_ID, CHILD_ID)).thenReturn(true);
    when(clinicalConsentRepository.isAgreedClinicalConsent(CONSENT_ID, GUARDIAN_ID, CHILD_ID))
        .thenReturn(true);
    when(childRepository.findById(CHILD_ID)).thenReturn(Optional.of(child));
    when(recordRepository.save(any(ChildScreeningRecord.class)))
        .thenAnswer(invocation -> invocation.getArgument(0));
  }

  @Test
  @DisplayName("등록부에 없는 검사 도구는 기록하지 않는다")
  void rejectsUnknownInstrument() {
    // 막지 않으면 임의의 검사명이 아동 기록에 남는다.
    assertThatThrownBy(() -> service.register(GUARDIAN_ID, CHILD_ID, request("MADE_UP_TEST")))
        .isInstanceOf(BusinessException.class)
        .hasMessage(ScreeningRecordErrorCode.SCREENING_INSTRUMENT_NOT_ALLOWED.getMessage());
    verify(recordRepository, never()).save(any());
  }

  @Test
  @DisplayName("임상 기록 보관 동의 이력이 없으면 기록하지 않는다")
  void rejectsWithoutConsent() {
    // 요청 본문의 boolean 이 아니라 동의 이력을 직접 확인한다.
    when(clinicalConsentRepository.isAgreedClinicalConsent(anyLong(), anyLong(), anyLong()))
        .thenReturn(false);

    assertThatThrownBy(
            () ->
                service.register(GUARDIAN_ID, CHILD_ID, request(ScreeningInstrumentRegistry.K_DST)))
        .isInstanceOf(BusinessException.class)
        .hasMessage(ScreeningRecordErrorCode.SCREENING_CONSENT_REQUIRED.getMessage());
    verify(recordRepository, never()).save(any());
  }

  @Test
  @DisplayName("연결되지 않은 보호자는 기록하지 않는다")
  void rejectsUnrelatedGuardian() {
    when(guardianAccessRepository.hasChildAccess(anyLong(), anyLong())).thenReturn(false);

    assertThatThrownBy(
            () ->
                service.register(GUARDIAN_ID, CHILD_ID, request(ScreeningInstrumentRegistry.K_DST)))
        .isInstanceOf(BusinessException.class)
        .hasMessage(ScreeningRecordErrorCode.SCREENING_ACCESS_DENIED.getMessage());
    verify(clinicalConsentRepository, never())
        .isAgreedClinicalConsent(anyLong(), anyLong(), anyLong());
  }

  @Test
  @DisplayName("보호자 입력은 언제나 미검증이며 공식 결과가 아니다")
  void guardianInputIsNeverVerified() {
    // 검증 주체가 없는데 검증된 것으로 저장되면, 화면이 이 값을 공식 결과로 보여 주게 된다.
    service.register(GUARDIAN_ID, CHILD_ID, request(ScreeningInstrumentRegistry.K_DST));

    ArgumentCaptor<ChildScreeningRecord> captor =
        ArgumentCaptor.forClass(ChildScreeningRecord.class);
    verify(recordRepository).save(captor.capture());
    ChildScreeningRecord saved = captor.getValue();

    assertThat(saved.isSourceVerified()).isFalse();
    assertThat(saved.getVerificationMethod()).isNull();
    assertThat(saved.getSourceAuthorityType())
        .isEqualTo(ScreeningSourceAuthorityType.GUARDIAN_REPORTED);
    assertThat(saved.isAiRecalculated()).isFalse();
    assertThat(saved.getDiagnosticStatus()).isEqualTo(ChildScreeningRecord.DIAGNOSTIC_STATUS);
    assertThat(saved.getPayloadHash()).hasSize(64);
  }

  @Test
  @DisplayName("삭제는 행을 지우지 않고 시각을 남긴다")
  void deleteKeepsTheRowAndStampsTheTime() {
    ChildScreeningRecord record = savedRecord();
    when(recordRepository.findByIdAndChildIdAndDeletedAtIsNull(5L, CHILD_ID))
        .thenReturn(Optional.of(record));

    service.delete(GUARDIAN_ID, CHILD_ID, 5L);

    // 조회에서는 즉시 빠지지만 무엇이 언제 사라졌는지는 남는다.
    assertThat(record.isDeleted()).isTrue();
    assertThat(record.getDeletedAt()).isNotNull();
    verify(recordRepository, never()).delete(any());
  }

  @Test
  @DisplayName("다른 아이의 기록은 지울 수 없다")
  void deleteRejectsForeignRecord() {
    when(recordRepository.findByIdAndChildIdAndDeletedAtIsNull(anyLong(), anyLong()))
        .thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.delete(GUARDIAN_ID, CHILD_ID, 5L))
        .isInstanceOf(BusinessException.class)
        .hasMessage(ScreeningRecordErrorCode.SCREENING_RECORD_NOT_FOUND.getMessage());
  }

  private ChildScreeningRecord savedRecord() {
    return ChildScreeningRecord.create(
        child,
        ScreeningInstrumentRegistry.K_DST,
        null,
        ScreeningRespondent.GUARDIAN,
        LocalDate.of(2026, 7, 1),
        62,
        ScreeningSourceAuthorityType.GUARDIAN_REPORTED,
        "영유아건강검진",
        "FOLLOW_UP_RECOMMENDED",
        "심화평가권고",
        "공식 검진 기관",
        null,
        null,
        CONSENT_ID,
        null,
        "0".repeat(64),
        java.time.LocalDateTime.of(2026, 8, 8, 0, 0));
  }

  private RegisterScreeningRecordRequest request(String instrumentId) {
    return new RegisterScreeningRecordRequest(
        instrumentId,
        null,
        ScreeningRespondent.GUARDIAN,
        LocalDate.of(2026, 7, 1),
        62,
        "영유아건강검진",
        "FOLLOW_UP_RECOMMENDED",
        "심화평가권고",
        "공식 검진 기관",
        List.of(new RegisterScreeningRecordRequest.DomainResult("언어", "심화평가권고")),
        null,
        null,
        List.of("소아청소년과"),
        null,
        CONSENT_ID);
  }
}
