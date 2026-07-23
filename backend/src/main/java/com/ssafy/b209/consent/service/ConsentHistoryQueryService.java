package com.ssafy.b209.consent.service;

import com.ssafy.b209.consent.dto.response.ConsentHistoryItemResponse;
import com.ssafy.b209.consent.dto.response.ConsentHistoryPageResponse;
import com.ssafy.b209.consent.exception.ConsentErrorCode;
import com.ssafy.b209.consent.repository.ConsentAuthorizationRepository;
import com.ssafy.b209.consent.repository.ConsentHistoryPage;
import com.ssafy.b209.consent.repository.ConsentHistoryRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDate;
import java.time.ZoneOffset;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증 사용자가 접근할 수 있는 버전별 동의·철회 이력을 조회한다.
 *
 * <p>특정 아동을 조회할 때 보호자 연결 관계를 먼저 검증하며, 감사용 접속 정보는 응답으로 노출하지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class ConsentHistoryQueryService {

  private final ConsentHistoryRepository historyRepository;
  private final ConsentAuthorizationRepository authorizationRepository;

  /**
   * 동의 이력 조회 서비스를 구성한다.
   *
   * @param historyRepository 버전별 동의 이력 조회 저장소
   * @param authorizationRepository 보호자-아동 관계 확인 저장소
   */
  public ConsentHistoryQueryService(
      ConsentHistoryRepository historyRepository,
      ConsentAuthorizationRepository authorizationRepository) {
    this.historyRepository = historyRepository;
    this.authorizationRepository = authorizationRepository;
  }

  /**
   * 동의 이력을 필터와 페이지 조건에 맞춰 최신순으로 조회한다.
   *
   * @param userId 인증 사용자 식별자
   * @param childId 특정 아동 필터, 전체 접근 가능 이력이면 {@code null}
   * @param termCode 약관 코드 필터
   * @param from 기록일 하한
   * @param to 기록일 상한
   * @param page 0부터 시작하는 페이지
   * @param size 페이지 크기
   * @return 동의 이력 페이지
   * @throws BusinessException 지정 아동의 연결 보호자가 아닌 경우
   */
  public ConsentHistoryPageResponse getHistory(
      Long userId,
      Long childId,
      String termCode,
      LocalDate from,
      LocalDate to,
      int page,
      int size) {
    if (childId != null && !authorizationRepository.hasGuardianChildRelation(userId, childId)) {
      throw new BusinessException(ConsentErrorCode.CONSENT_ACTOR_NOT_GUARDIAN);
    }
    String normalizedTermCode = termCode == null || termCode.isBlank() ? null : termCode.trim();
    ConsentHistoryPage result =
        historyRepository.findAccessibleHistory(
            userId,
            childId,
            normalizedTermCode,
            from == null ? null : from.atStartOfDay(),
            to == null ? null : to.plusDays(1).atStartOfDay(),
            page,
            size);
    var content =
        result.content().stream()
            .map(
                row ->
                    new ConsentHistoryItemResponse(
                        row.consentRecordId(),
                        row.termId(),
                        row.termCode(),
                        row.targetScope(),
                        row.required(),
                        row.version(),
                        row.title(),
                        row.childId(),
                        row.action(),
                        row.recordedAt().toInstant(ZoneOffset.UTC)))
            .toList();
    int totalPages = (int) Math.min(Integer.MAX_VALUE, (result.totalElements() + size - 1) / size);
    boolean first = page == 0;
    boolean last = page + 1 >= totalPages;
    return new ConsentHistoryPageResponse(
        content, page, size, result.totalElements(), totalPages, first, last, !last);
  }
}
