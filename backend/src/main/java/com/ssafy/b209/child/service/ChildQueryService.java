package com.ssafy.b209.child.service;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.dto.response.ChildSummaryResponse;
import com.ssafy.b209.child.dto.response.ChildTutorialProgressResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildDetailProjection;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.child.repository.ChildSummaryProjection;
import com.ssafy.b209.child.repository.ChildTutorialProgressProjection;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Period;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 보호자가 조회할 수 있는 아동 상세 프로필을 조립한다.
 *
 * <p>아동 존재 여부와 보호자 소유권을 Repository Query에 함께 적용하고, 조회일 기준 만 나이와 공개 가능한 응답 필드를 계산한다. 조회 과정에서 아동 상태를
 * 변경하지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class ChildQueryService {

  private final ChildRepository childRepository;
  private final Clock clock;

  /**
   * 운영 시각을 기준으로 아동 상세 조회 서비스를 생성한다.
   *
   * @param childRepository 아동 프로필과 보호자 관계를 조회할 저장소
   */
  @Autowired
  public ChildQueryService(ChildRepository childRepository) {
    this(childRepository, Clock.systemUTC());
  }

  ChildQueryService(ChildRepository childRepository, Clock clock) {
    this.childRepository = childRepository;
    this.clock = clock;
  }

  /**
   * 요청 보호자에게 연결된 활성 아동의 상세 프로필을 조회한다.
   *
   * <p>존재하지 않음, Soft Delete와 소유권 실패는 모두 동일한 오류로 처리한다.
   *
   * @param guardianUserId 조회를 요청한 보호자 사용자 식별자
   * @param childId 조회할 아동 식별자
   * @return 현재 보호자와의 관계 및 응답 방식을 포함한 상세 프로필
   * @throws BusinessException 조회 가능한 아동이 없는 경우
   */
  public ChildDetailResponse getChild(Long guardianUserId, Long childId) {
    ChildDetailProjection child =
        childRepository
            .findDetailByGuardianUserIdAndChildId(guardianUserId, childId)
            .orElseThrow(() -> new BusinessException(ChildErrorCode.CHILD_NOT_FOUND));

    return new ChildDetailResponse(
        child.getChildId(),
        child.getNickname(),
        child.getBirthDate(),
        Period.between(child.getBirthDate(), LocalDate.now(clock)).getYears(),
        child.getProfileImageUrl(),
        child.getPreferredCharacter(),
        QuestionDifficulty.valueOf(child.getQuestionDifficulty()),
        childRepository.findResponseModesByChildId(childId),
        ChildTutorialStatus.valueOf(child.getTutorialStatus()),
        ChildProfileStatus.valueOf(child.getProfileStatus()),
        child.getRelationshipType(),
        child.getCreatedAt().toInstant(ZoneOffset.UTC),
        child.getUpdatedAt().toInstant(ZoneOffset.UTC));
  }

  /**
   * 요청 보호자에게 연결된 활성 아동 목록을 등록 순서로 조회한다.
   *
   * <p>연결된 아동이 없으면 빈 목록을 반환하며 각 항목에 조회일 기준 만 나이를 포함한다.
   *
   * @param guardianUserId 목록을 조회할 보호자 사용자 식별자
   * @return 등록 순서가 적용된 아동 요약 목록
   */
  public List<ChildSummaryResponse> getChildren(Long guardianUserId) {
    LocalDate today = LocalDate.now(clock);
    return childRepository.findSummariesByGuardianUserId(guardianUserId).stream()
        .map(child -> toSummary(child, today))
        .toList();
  }

  /**
   * 연결된 보호자가 아동의 현재 Tutorial 진행 정보를 조회한다.
   *
   * <p>조회 가능한 아동이 없으면 존재하지 않는 아동과 권한이 없는 아동을 구분하지 않고 동일한 오류를 반환한다. 이 메서드는 진행 상태를 변경하지 않는다.
   *
   * @param guardianUserId 조회를 요청한 보호자 사용자 식별자
   * @param childId Tutorial 상태를 조회할 아동 식별자
   * @return 현재 Tutorial 상태와 복원에 필요한 마지막 단계·시각
   * @throws BusinessException 아동이 없거나 삭제됐거나 보호자에게 연결되지 않은 경우
   */
  public ChildTutorialProgressResponse getTutorialProgress(Long guardianUserId, Long childId) {
    ChildTutorialProgressProjection progress =
        childRepository
            .findTutorialProgressByGuardianUserIdAndChildId(guardianUserId, childId)
            .orElseThrow(() -> new BusinessException(ChildErrorCode.CHILD_NOT_FOUND));

    return new ChildTutorialProgressResponse(
        progress.getChildId(),
        ChildTutorialStatus.valueOf(progress.getTutorialStatus()),
        progress.getLastStep(),
        toInstant(progress.getCompletedAt()),
        toInstant(progress.getUpdatedAt()));
  }

  private Instant toInstant(LocalDateTime value) {
    return value == null ? null : value.toInstant(ZoneOffset.UTC);
  }

  private ChildSummaryResponse toSummary(ChildSummaryProjection child, LocalDate today) {
    LocalDateTime lastActivityAt = child.getLastActivityAt();
    return new ChildSummaryResponse(
        child.getChildId(),
        child.getNickname(),
        child.getBirthDate(),
        Period.between(child.getBirthDate(), today).getYears(),
        child.getProfileImageUrl(),
        child.getPreferredCharacter(),
        QuestionDifficulty.valueOf(child.getQuestionDifficulty()),
        ChildTutorialStatus.valueOf(child.getTutorialStatus()),
        ChildProfileStatus.valueOf(child.getProfileStatus()),
        child.getRelationshipType(),
        new ChildSummaryResponse.RecentActivity(
            lastActivityAt == null ? null : lastActivityAt.toInstant(ZoneOffset.UTC),
            child.getTotalActivityCount()));
  }
}
