package com.ssafy.b209.consent.service;

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
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 활성 약관과 보호자 관계를 검증하고 최초 동의 행위를 append-only 이력으로 저장한다. */
@Service
public class ConsentRegistrationService {

  private final ConsentTermRepository termRepository;
  private final ConsentRecordRepository recordRepository;
  private final ConsentAuthorizationRepository authorizationRepository;
  private final ConsentSubjectHasher subjectHasher;
  private final Clock clock;

  /**
   * 동의 등록 Use Case를 구성한다.
   *
   * @param termRepository 버전 약관 저장소
   * @param recordRepository append-only 동의 이력 저장소
   * @param authorizationRepository 보호자-아동 관계 확인 저장소
   * @param subjectHasher 비식별 대상 참조 hash 생성기
   * @param clock 약관 시행과 기록 시각 기준
   */
  public ConsentRegistrationService(
      ConsentTermRepository termRepository,
      ConsentRecordRepository recordRepository,
      ConsentAuthorizationRepository authorizationRepository,
      ConsentSubjectHasher subjectHasher,
      Clock clock) {
    this.termRepository = termRepository;
    this.recordRepository = recordRepository;
    this.authorizationRepository = authorizationRepository;
    this.subjectHasher = subjectHasher;
    this.clock = clock;
  }

  /**
   * 최초 동의 요청이 현재 필수 약관을 충족하는지 확인하고 각 행위를 새 이력으로 저장한다.
   *
   * @param actorUserId Access Token으로 인증된 동의 처리 사용자 ID
   * @param request 아동 ID와 약관별 동의 행위
   * @param ipAddress 요청 원격 IP, 확인할 수 없으면 {@code null}
   * @param userAgent 요청 User-Agent, 확인할 수 없으면 {@code null}
   * @return 저장 수와 필수 동의 충족 여부
   * @throws BusinessException 약관, 필수 동의, 적용 범위 또는 보호자 관계가 유효하지 않은 경우
   */
  @Transactional
  public ConsentRegistrationResponse register(
      Long actorUserId, CreateConsentRequest request, String ipAddress, String userAgent) {
    if (request.childId() != null
        && !authorizationRepository.hasGuardianChildRelation(actorUserId, request.childId())) {
      throw new BusinessException(ConsentErrorCode.CONSENT_ACTOR_NOT_GUARDIAN);
    }

    Map<Long, ConsentAction> requestedActions = requestedActions(request.agreements());
    List<ConsentTerm> terms = termRepository.findAllById(requestedActions.keySet());
    if (terms.size() != requestedActions.size()) {
      throw new BusinessException(ConsentErrorCode.TERM_NOT_FOUND);
    }

    LocalDateTime now = LocalDateTime.now(clock);
    validateReferencedTerms(terms, request.childId(), now);
    validateRequiredTerms(requestedActions, request.childId(), now);

    List<ConsentRecord> records =
        terms.stream()
            .map(
                term ->
                    ConsentRecord.record(
                        term,
                        actorUserId,
                        childSubjectId(term, request.childId()),
                        subjectHash(term, actorUserId, request.childId()),
                        requestedActions.get(term.getId()),
                        ipAddress,
                        userAgent,
                        now))
            .toList();
    recordRepository.saveAll(records);
    return new ConsentRegistrationResponse(request.childId(), records.size(), true, now);
  }

  private Map<Long, ConsentAction> requestedActions(List<ConsentAgreementRequest> agreements) {
    Map<Long, ConsentAction> actions = new HashMap<>();
    for (ConsentAgreementRequest agreement : agreements) {
      if (actions.put(agreement.termId(), agreement.action()) != null) {
        throw new BusinessException(ConsentErrorCode.CONSENT_REQUEST_INVALID);
      }
    }
    return actions;
  }

  private void validateReferencedTerms(List<ConsentTerm> terms, Long childId, LocalDateTime now) {
    boolean includesChildTerm = false;
    for (ConsentTerm term : terms) {
      if (!term.isEffectiveAt(now)) {
        throw new BusinessException(ConsentErrorCode.TERM_VERSION_INACTIVE);
      }
      if (term.getTargetScope() == ConsentTargetScope.CHILD && childId == null) {
        throw new BusinessException(ConsentErrorCode.CONSENT_REQUEST_INVALID);
      }
      includesChildTerm |= term.getTargetScope() == ConsentTargetScope.CHILD;
    }
    if (childId != null && !includesChildTerm) {
      throw new BusinessException(ConsentErrorCode.CONSENT_REQUEST_INVALID);
    }
  }

  private void validateRequiredTerms(
      Map<Long, ConsentAction> requestedActions, Long childId, LocalDateTime now) {
    Set<ConsentTargetScope> applicableScopes =
        childId == null
            ? Set.of(ConsentTargetScope.USER)
            : Set.of(ConsentTargetScope.USER, ConsentTargetScope.CHILD);
    Set<Long> requiredTermIds =
        termRepository.findAllByActiveTrue().stream()
            .filter(term -> term.isEffectiveAt(now))
            .filter(ConsentTerm::isRequired)
            .filter(term -> applicableScopes.contains(term.getTargetScope()))
            .map(ConsentTerm::getId)
            .collect(Collectors.toSet());
    boolean satisfied =
        requiredTermIds.stream()
            .allMatch(termId -> requestedActions.get(termId) == ConsentAction.AGREE);
    if (!satisfied) {
      throw new BusinessException(ConsentErrorCode.REQUIRED_CONSENT_MISSING);
    }
  }

  private Long childSubjectId(ConsentTerm term, Long childId) {
    return term.getTargetScope() == ConsentTargetScope.CHILD ? childId : null;
  }

  private String subjectHash(ConsentTerm term, Long actorUserId, Long childId) {
    Long subjectId = term.getTargetScope() == ConsentTargetScope.CHILD ? childId : actorUserId;
    return subjectHasher.hash(term.getTargetScope(), subjectId);
  }
}
