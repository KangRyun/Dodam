package com.ssafy.b209.screening.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.screening.domain.ChildScreeningRecord;
import com.ssafy.b209.screening.domain.ChildScreeningRecordDomain;
import com.ssafy.b209.screening.domain.ChildScreeningReferralOption;
import com.ssafy.b209.screening.dto.response.ScreeningRecordResponse;
import com.ssafy.b209.screening.dto.response.ScreeningRecordResponse.DomainResultResponse;
import com.ssafy.b209.screening.dto.response.ScreeningSummaryResponse;
import com.ssafy.b209.screening.exception.ScreeningRecordErrorCode;
import com.ssafy.b209.screening.registry.ScreeningInstrument;
import com.ssafy.b209.screening.registry.ScreeningInstrumentRegistry;
import com.ssafy.b209.screening.registry.ScreeningOfferState;
import com.ssafy.b209.screening.repository.ChildScreeningRecordDomainRepository;
import com.ssafy.b209.screening.repository.ChildScreeningRecordRepository;
import com.ssafy.b209.screening.repository.ChildScreeningReferralOptionRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자가 옮겨 적은 선별 결과를 읽어 리포트·목록 화면에 실을 형태로 만든다.
 *
 * <p>이 서비스가 지키는 것 하나는 <strong>제공 가능한 도구 목록을 만들어 내보내지 않는 것</strong>이다. 등록부의 모든 도구가 승인 전이라 지금은 제공할 것이
 * 없고, 승인 전 도구를 '곧 제공' 목록처럼 늘어놓으면 그 자체가 검사 권유가 된다.
 */
@Service
public class ScreeningRecordQueryService {

  /** 제공하는 선별검사가 없을 때의 문구다. '아직 준비 중'처럼 곧 생길 것으로 읽히지 않게 쓴다. */
  private static final String NOT_OFFERED_MESSAGE =
      "이 앱은 표준화 선별검사를 제공하지 않아요. 그림일기 기록은 검사 결과가 아니에요.";

  /** 보호자가 직접 기록해 둔 결과가 있을 때의 문구다. */
  private static final String RECORDED_MESSAGE =
      "보호자가 직접 입력한 검사 기록이에요. 앱이 확인하거나 채점한 결과가 아니며, 그림일기 관찰과는 별개예요.";

  private final GuardianResourceAccessRepository guardianAccessRepository;
  private final ChildScreeningRecordRepository recordRepository;
  private final ChildScreeningRecordDomainRepository domainRepository;
  private final ChildScreeningReferralOptionRepository referralOptionRepository;

  /**
   * 선별 결과 조회 서비스를 구성한다.
   *
   * @param guardianAccessRepository 보호자-아동 접근 확인 경계
   * @param recordRepository 선별 결과 기록 저장소
   * @param domainRepository 영역별 라벨 저장소
   * @param referralOptionRepository 후속 상담 경로 저장소
   */
  public ScreeningRecordQueryService(
      GuardianResourceAccessRepository guardianAccessRepository,
      ChildScreeningRecordRepository recordRepository,
      ChildScreeningRecordDomainRepository domainRepository,
      ChildScreeningReferralOptionRepository referralOptionRepository) {
    this.guardianAccessRepository = guardianAccessRepository;
    this.recordRepository = recordRepository;
    this.domainRepository = domainRepository;
    this.referralOptionRepository = referralOptionRepository;
  }

  /**
   * 보호자 요청으로 아동의 선별 요약을 만든다.
   *
   * <p>읽기라고 접근 확인을 건너뛰지 않는다 — 여기 담기는 것은 아이의 의료 기록이고, 조회가 곧 열람이다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param childId 아동 식별자
   * @return 상태·문구·기록을 담은 요약
   */
  @Transactional(readOnly = true)
  public ScreeningSummaryResponse summarizeForGuardian(Long guardianUserId, Long childId) {
    if (!guardianAccessRepository.hasChildAccess(guardianUserId, childId)) {
      throw new BusinessException(ScreeningRecordErrorCode.SCREENING_ACCESS_DENIED);
    }
    return summarize(childId);
  }

  /**
   * 아동의 선별 요약을 만든다. 기록이 없어도 요약은 나간다 — 침묵하면 보호자는 앱이 선별을 해 준다고 오해한다.
   *
   * <p>접근 확인을 하지 않는다. 이미 보호자 권한을 확인한 호출부(리포트 상세)에서만 쓴다.
   *
   * @param childId 아동 식별자
   * @return 상태·문구·기록을 담은 요약
   */
  @Transactional(readOnly = true)
  public ScreeningSummaryResponse summarize(Long childId) {
    List<ScreeningRecordResponse> records = findRecords(childId);
    ScreeningOfferState state =
        records.isEmpty()
            ? ScreeningOfferState.NOT_OFFERED
            : ScreeningOfferState.EXTERNAL_RESULT_AVAILABLE;
    String message = records.isEmpty() ? NOT_OFFERED_MESSAGE : RECORDED_MESSAGE;
    return new ScreeningSummaryResponse(state.name(), message, records);
  }

  /**
   * 아동의 살아 있는 기록을 최근 실시일 순으로 읽는다.
   *
   * @param childId 아동 식별자
   * @return 기록 목록이며 없으면 빈 목록
   */
  @Transactional(readOnly = true)
  public List<ScreeningRecordResponse> findRecords(Long childId) {
    List<ChildScreeningRecord> records =
        recordRepository.findByChildIdAndDeletedAtIsNullOrderByCompletedAtDesc(childId);
    if (records.isEmpty()) {
      return List.of();
    }
    // 자식 두 종류를 한 번씩만 읽어 묶는다 — 기록마다 조회하면 N+1 이 된다.
    List<Long> recordIds = records.stream().map(ChildScreeningRecord::getId).toList();
    Map<Long, List<DomainResultResponse>> domains = new LinkedHashMap<>();
    for (ChildScreeningRecordDomain domain :
        domainRepository.findByScreeningRecord_IdInOrderByDisplayOrderAsc(recordIds)) {
      domains
          .computeIfAbsent(domain.getScreeningRecordId(), key -> new ArrayList<>())
          .add(new DomainResultResponse(domain.getDomainName(), domain.getResultLabel()));
    }
    Map<Long, List<String>> referrals = new LinkedHashMap<>();
    for (ChildScreeningReferralOption option :
        referralOptionRepository.findByScreeningRecord_IdInOrderByDisplayOrderAsc(recordIds)) {
      referrals
          .computeIfAbsent(option.getScreeningRecordId(), key -> new ArrayList<>())
          .add(option.getReferralOption());
    }
    return records.stream().map(record -> toResponse(record, domains, referrals)).toList();
  }

  private ScreeningRecordResponse toResponse(
      ChildScreeningRecord record,
      Map<Long, List<DomainResultResponse>> domains,
      Map<Long, List<String>> referrals) {
    // 필수 고지는 등록부가 소유한다. 보호자가 입력할 수 있게 두면 고지 문구가 결과마다 달라진다.
    String disclosure =
        ScreeningInstrumentRegistry.find(record.getInstrumentId())
            .map(ScreeningInstrument::requiredDisclosure)
            .orElse(null);
    return new ScreeningRecordResponse(
        record.getId(),
        record.getInstrumentId(),
        ScreeningInstrumentRegistry.find(record.getInstrumentId())
            .map(ScreeningInstrument::displayName)
            .orElse(record.getInstrumentId()),
        record.getInstrumentVersion(),
        record.getRespondent().name(),
        record.getCompletedAt(),
        record.getSourceAuthorityType().name(),
        record.getSourceAuthorityName(),
        record.isSourceVerified(),
        record.getOfficialResultCode(),
        record.getOfficialResultText(),
        record.getDiagnosticStatus(),
        record.getScoredBy(),
        disclosure,
        domains.getOrDefault(record.getId(), List.of()),
        record.getFollowupLevel() == null ? null : record.getFollowupLevel().name(),
        record.getFollowupMessage(),
        referrals.getOrDefault(record.getId(), List.of()));
  }
}
