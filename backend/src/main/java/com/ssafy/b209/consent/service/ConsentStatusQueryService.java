package com.ssafy.b209.consent.service;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.domain.ConsentTerm;
import com.ssafy.b209.consent.dto.response.ConsentStatusItemResponse;
import com.ssafy.b209.consent.dto.response.ConsentStatusResponse;
import com.ssafy.b209.consent.exception.ConsentErrorCode;
import com.ssafy.b209.consent.repository.ConsentAuthorizationRepository;
import com.ssafy.b209.consent.repository.ConsentStatusRepository;
import com.ssafy.b209.consent.repository.ConsentTermRepository;
import com.ssafy.b209.consent.repository.LatestConsentAction;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * append-only 동의 이력에서 사용자와 선택 아동의 현재 동의 현황을 계산한다.
 *
 * <p>서버 기준 시각으로 시행 중인 활성 약관을 대상으로 하며, 약관별 가장 최근 행위가 동의인지로 현재 동의 여부를 판정한다.
 */
@Service
@Transactional(readOnly = true)
public class ConsentStatusQueryService {

  private final ConsentTermRepository termRepository;
  private final ConsentStatusRepository statusRepository;
  private final ConsentAuthorizationRepository authorizationRepository;
  private final Clock clock;

  /**
   * 동의 현황 조회 서비스를 구성한다.
   *
   * @param termRepository 버전 약관 저장소
   * @param statusRepository 약관별 최신 동의 행위 조회 저장소
   * @param authorizationRepository 보호자-아동 관계 확인 저장소
   */
  @Autowired
  public ConsentStatusQueryService(
      ConsentTermRepository termRepository,
      ConsentStatusRepository statusRepository,
      ConsentAuthorizationRepository authorizationRepository) {
    this(termRepository, statusRepository, authorizationRepository, Clock.systemUTC());
  }

  ConsentStatusQueryService(
      ConsentTermRepository termRepository,
      ConsentStatusRepository statusRepository,
      ConsentAuthorizationRepository authorizationRepository,
      Clock clock) {
    this.termRepository = termRepository;
    this.statusRepository = statusRepository;
    this.authorizationRepository = authorizationRepository;
    this.clock = clock;
  }

  /**
   * 사용자 본인과 선택 아동에 대한 현재 동의 현황을 조회한다.
   *
   * @param userId 인증된 사용자 식별자
   * @param childId 아동 대상 현황을 함께 조회할 아동 식별자, 사용자 약관만 조회하면 {@code null}
   * @return 필수 동의 충족 여부와 약관별 현재 동의 상태
   * @throws BusinessException 아동을 지정했으나 연결 보호자가 아닌 경우
   */
  public ConsentStatusResponse getConsentStatus(Long userId, Long childId) {
    if (childId != null && !authorizationRepository.hasGuardianChildRelation(userId, childId)) {
      throw new BusinessException(ConsentErrorCode.CONSENT_ACTOR_NOT_GUARDIAN);
    }

    LocalDateTime now = LocalDateTime.now(clock);
    Set<ConsentTargetScope> applicableScopes =
        childId == null
            ? Set.of(ConsentTargetScope.USER)
            : Set.of(ConsentTargetScope.USER, ConsentTargetScope.CHILD);
    List<ConsentTerm> applicableTerms =
        termRepository.findAllByActiveTrue().stream()
            .filter(term -> term.isEffectiveAt(now))
            .filter(term -> applicableScopes.contains(term.getTargetScope()))
            .sorted(Comparator.comparing(ConsentTerm::getId))
            .toList();

    Map<Long, LatestConsentAction> latestByTerm = new HashMap<>();
    for (LatestConsentAction action : statusRepository.findLatestUserScopeActions(userId)) {
      latestByTerm.put(action.termId(), action);
    }
    if (childId != null) {
      for (LatestConsentAction action : statusRepository.findLatestChildScopeActions(childId)) {
        latestByTerm.put(action.termId(), action);
      }
    }

    List<ConsentStatusItemResponse> items = new ArrayList<>();
    boolean requiredConsentsSatisfied = true;
    for (ConsentTerm term : applicableTerms) {
      LatestConsentAction latest = latestByTerm.get(term.getId());
      boolean agreed = latest != null && latest.action() == ConsentAction.AGREE;
      Instant recordedAt = latest == null ? null : latest.recordedAt().toInstant(ZoneOffset.UTC);
      items.add(
          new ConsentStatusItemResponse(
              term.getId(),
              term.getTermCode(),
              term.isRequired(),
              term.getVersion(),
              agreed,
              recordedAt));
      if (term.isRequired() && !agreed) {
        requiredConsentsSatisfied = false;
      }
    }
    return new ConsentStatusResponse(childId, requiredConsentsSatisfied, items);
  }
}
