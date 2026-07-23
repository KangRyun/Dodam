package com.ssafy.b209.consent.service;

import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.domain.ConsentTerm;
import com.ssafy.b209.consent.dto.response.ConsentTermResponse;
import com.ssafy.b209.consent.repository.ConsentTermRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Comparator;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 현재 시행 중인 활성 약관 목록을 공개 조회 계약으로 변환한다.
 *
 * <p>서버 기준 시각으로 시행 여부를 판정하며 선택한 적용 범위와 버전으로 결과를 좁힐 수 있다.
 */
@Service
@Transactional(readOnly = true)
public class ConsentTermQueryService {

  private final ConsentTermRepository consentTermRepository;
  private final Clock clock;

  /**
   * 약관 조회 서비스를 구성한다.
   *
   * @param consentTermRepository 버전 약관 저장소
   */
  @Autowired
  public ConsentTermQueryService(ConsentTermRepository consentTermRepository) {
    this(consentTermRepository, Clock.systemUTC());
  }

  ConsentTermQueryService(ConsentTermRepository consentTermRepository, Clock clock) {
    this.consentTermRepository = consentTermRepository;
    this.clock = clock;
  }

  /**
   * 현재 시행 중인 활성 약관을 식별자 순으로 조회한다.
   *
   * @param targetScope 적용 범위 필터, 전체 범위면 {@code null}
   * @param version 버전 필터, 전체 버전이면 {@code null} 또는 빈 값
   * @return 조건에 맞는 현재 적용 약관 목록
   */
  public List<ConsentTermResponse> getActiveTerms(ConsentTargetScope targetScope, String version) {
    LocalDateTime now = LocalDateTime.now(clock);
    return consentTermRepository.findAllByActiveTrue().stream()
        .filter(term -> term.isEffectiveAt(now))
        .filter(term -> targetScope == null || term.getTargetScope() == targetScope)
        .filter(term -> version == null || version.isBlank() || version.equals(term.getVersion()))
        .sorted(Comparator.comparing(ConsentTerm::getId))
        .map(this::toResponse)
        .toList();
  }

  private ConsentTermResponse toResponse(ConsentTerm term) {
    return new ConsentTermResponse(
        term.getId(),
        term.getTermCode(),
        term.getTargetScope(),
        term.isRequired(),
        term.getVersion(),
        term.getTitle(),
        term.getContentUrl(),
        term.getContentHtml(),
        term.getEffectiveAt().toInstant(ZoneOffset.UTC));
  }
}
