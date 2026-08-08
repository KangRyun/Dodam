package com.ssafy.b209.screening.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.screening.domain.ChildScreeningRecord;
import com.ssafy.b209.screening.domain.ChildScreeningRecordDomain;
import com.ssafy.b209.screening.domain.ChildScreeningReferralOption;
import com.ssafy.b209.screening.domain.ScreeningSourceAuthorityType;
import com.ssafy.b209.screening.dto.request.RegisterScreeningRecordRequest;
import com.ssafy.b209.screening.exception.ScreeningRecordErrorCode;
import com.ssafy.b209.screening.registry.ScreeningInstrumentRegistry;
import com.ssafy.b209.screening.repository.ChildScreeningRecordDomainRepository;
import com.ssafy.b209.screening.repository.ChildScreeningRecordRepository;
import com.ssafy.b209.screening.repository.ChildScreeningReferralOptionRepository;
import com.ssafy.b209.screening.repository.ClinicalConsentRepository;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자가 다른 곳에서 받은 선별 결과를 기록하고 지운다.
 *
 * <p>등록 전에 네 가지를 확인한다. 하나라도 빠지면 의료 기록이 근거 없이 남는다.
 *
 * <ol>
 *   <li>보호자가 그 아동의 연결 보호자인가
 *   <li>도구가 등록부 allow-list 안에 있는가 — 없으면 임의의 검사명이 아동 기록에 남는다
 *   <li>임상 기록 보관 <strong>동의 이력이 실제로 있는가</strong> — 요청 본문의 boolean 을 믿지 않는다
 *   <li>원본을 고정했는가 — 등록 당시 본문의 해시를 남겨 나중에 값이 바뀌었는지 확인할 수 있게 한다
 * </ol>
 */
@Service
public class ScreeningRecordCommandService {

  private final GuardianResourceAccessRepository guardianAccessRepository;
  private final ChildRepository childRepository;
  private final ChildScreeningRecordRepository recordRepository;
  private final ChildScreeningRecordDomainRepository domainRepository;
  private final ChildScreeningReferralOptionRepository referralOptionRepository;
  private final ClinicalConsentRepository clinicalConsentRepository;
  private final ObjectMapper objectMapper;
  private final Clock clock;

  /**
   * 선별 결과 등록·삭제 서비스를 구성한다.
   *
   * @param guardianAccessRepository 보호자-아동 접근 확인 경계
   * @param childRepository 아동 조회 저장소
   * @param recordRepository 선별 결과 기록 저장소
   * @param domainRepository 영역별 라벨 저장소
   * @param referralOptionRepository 후속 상담 경로 저장소
   * @param clinicalConsentRepository 임상 기록 보관 동의 확인 경계
   * @param objectMapper 원본 고정을 위한 직렬화 도구
   * @param clock 등록·삭제 시각을 제공하는 시계
   */
  public ScreeningRecordCommandService(
      GuardianResourceAccessRepository guardianAccessRepository,
      ChildRepository childRepository,
      ChildScreeningRecordRepository recordRepository,
      ChildScreeningRecordDomainRepository domainRepository,
      ChildScreeningReferralOptionRepository referralOptionRepository,
      ClinicalConsentRepository clinicalConsentRepository,
      ObjectMapper objectMapper,
      Clock clock) {
    this.guardianAccessRepository = guardianAccessRepository;
    this.childRepository = childRepository;
    this.recordRepository = recordRepository;
    this.domainRepository = domainRepository;
    this.referralOptionRepository = referralOptionRepository;
    this.clinicalConsentRepository = clinicalConsentRepository;
    this.objectMapper = objectMapper;
    this.clock = clock;
  }

  /**
   * 선별 결과를 기록한다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param childId 대상 아동 식별자
   * @param request 보호자가 옮겨 적은 결과
   * @return 저장된 기록 식별자
   */
  @Transactional
  public Long register(Long guardianUserId, Long childId, RegisterScreeningRecordRequest request) {
    requireChildAccess(guardianUserId, childId);
    if (ScreeningInstrumentRegistry.find(request.instrumentId()).isEmpty()) {
      throw new BusinessException(ScreeningRecordErrorCode.SCREENING_INSTRUMENT_NOT_ALLOWED);
    }
    if (!clinicalConsentRepository.isAgreedClinicalConsent(
        request.consentRecordId(), guardianUserId, childId)) {
      throw new BusinessException(ScreeningRecordErrorCode.SCREENING_CONSENT_REQUIRED);
    }
    Child child =
        childRepository
            .findById(childId)
            .orElseThrow(
                () -> new BusinessException(ScreeningRecordErrorCode.SCREENING_ACCESS_DENIED));

    ChildScreeningRecord record =
        recordRepository.save(
            ChildScreeningRecord.create(
                child,
                request.instrumentId(),
                request.instrumentVersion(),
                request.respondent(),
                request.completedAt(),
                request.childAgeMonthsAtAdministration(),
                // 공식 서비스 연동이 없으므로 들어오는 모든 기록은 보호자 보고다. 요청이 정하지 않는다.
                ScreeningSourceAuthorityType.GUARDIAN_REPORTED,
                request.sourceAuthorityName(),
                request.officialResultCode(),
                request.officialResultText(),
                request.scoredBy(),
                request.followupLevel(),
                request.followupMessage(),
                request.consentRecordId(),
                request.sourceDocumentRef(),
                payloadHash(request),
                LocalDateTime.now(clock)));

    List<ChildScreeningRecordDomain> domains = new ArrayList<>();
    List<RegisterScreeningRecordRequest.DomainResult> domainResults = request.domainResults();
    for (int index = 0; index < domainResults.size(); index++) {
      RegisterScreeningRecordRequest.DomainResult domain = domainResults.get(index);
      domains.add(
          ChildScreeningRecordDomain.create(
              record, domain.domainName(), domain.resultLabel(), index));
    }
    domainRepository.saveAll(domains);

    List<ChildScreeningReferralOption> options = new ArrayList<>();
    List<String> referralOptions = request.referralOptions();
    for (int index = 0; index < referralOptions.size(); index++) {
      options.add(ChildScreeningReferralOption.create(record, referralOptions.get(index), index));
    }
    referralOptionRepository.saveAll(options);
    return record.getId();
  }

  /**
   * 보호자가 기록을 지운다.
   *
   * <p>행을 삭제하지 않고 시각을 남긴다. 동의 이력과 같은 이유다 — <strong>무엇이 언제 사라졌는지</strong>가 감사 대상이고, 조회에서는 즉시 빠지므로
   * 보호자에게는 삭제와 다르지 않다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param childId 대상 아동 식별자
   * @param recordId 지울 기록 식별자
   */
  @Transactional
  public void delete(Long guardianUserId, Long childId, Long recordId) {
    requireChildAccess(guardianUserId, childId);
    ChildScreeningRecord record =
        recordRepository
            .findByIdAndChildIdAndDeletedAtIsNull(recordId, childId)
            .orElseThrow(
                () -> new BusinessException(ScreeningRecordErrorCode.SCREENING_RECORD_NOT_FOUND));
    record.markDeleted(LocalDateTime.now(clock));
  }

  private void requireChildAccess(Long guardianUserId, Long childId) {
    if (!guardianAccessRepository.hasChildAccess(guardianUserId, childId)) {
      throw new BusinessException(ScreeningRecordErrorCode.SCREENING_ACCESS_DENIED);
    }
  }

  /**
   * 등록 당시 요청 본문의 SHA-256을 만든다. 원본을 고정해 두어야 나중에 값이 바뀌었는지 확인할 수 있다.
   *
   * <p>직렬화가 실패해도 등록을 막지 않는다 — 해시는 무결성 확인용이고, 그것 때문에 보호자가 결과를 기록하지 못하는 편이 더 나쁘다. 대신 계산할 수 없었다는 사실을
   * 값으로 남긴다.
   */
  private String payloadHash(RegisterScreeningRecordRequest request) {
    try {
      byte[] payload = objectMapper.writeValueAsBytes(request);
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      return HexFormat.of().formatHex(digest.digest(payload));
    } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
      return "0".repeat(64);
    }
  }
}
