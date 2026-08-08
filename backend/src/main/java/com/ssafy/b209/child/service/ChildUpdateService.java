package com.ssafy.b209.child.service;

import com.ssafy.b209.child.domain.ResponseMode;
import com.ssafy.b209.child.dto.request.UpdateChildRequest;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildUpdateRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Period;
import java.util.LinkedHashSet;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 보호자의 아동 프로필 부분 수정 Use Case를 수행한다.
 *
 * <p>접근 가능한 활성 아동을 잠근 뒤 기본 정보, 요청 보호자 관계와 응답 방식을 한 Transaction에서 변경한다.
 */
@Service
public class ChildUpdateService {

  private static final int MINIMUM_AGE = 4;
  private static final int MAXIMUM_AGE = 12;

  private final ChildUpdateRepository childUpdateRepository;
  private final ChildQueryService childQueryService;
  private final ChildProfileImageLinkService profileImageLinkService;
  private final Clock clock;

  /**
   * 운영 시각을 기준으로 아동 프로필 수정 서비스를 생성한다.
   *
   * @param childUpdateRepository 아동 프로필을 변경할 저장소
   * @param childQueryService 변경 결과를 조회할 Service
   */
  @Autowired
  public ChildUpdateService(
      ChildUpdateRepository childUpdateRepository,
      ChildQueryService childQueryService,
      ChildProfileImageLinkService profileImageLinkService) {
    this(childUpdateRepository, childQueryService, profileImageLinkService, Clock.systemUTC());
  }

  ChildUpdateService(
      ChildUpdateRepository childUpdateRepository,
      ChildQueryService childQueryService,
      Clock clock) {
    this(childUpdateRepository, childQueryService, null, clock);
  }

  ChildUpdateService(
      ChildUpdateRepository childUpdateRepository,
      ChildQueryService childQueryService,
      ChildProfileImageLinkService profileImageLinkService,
      Clock clock) {
    this.childUpdateRepository = childUpdateRepository;
    this.childQueryService = childQueryService;
    this.profileImageLinkService = profileImageLinkService;
    this.clock = clock;
  }

  /**
   * 요청 보호자에게 연결된 아동 프로필에서 전달된 값만 변경한다.
   *
   * @param guardianUserId 변경을 요청한 보호자 사용자 식별자
   * @param childId 변경할 아동 식별자
   * @param request 변경할 아동 프로필 값
   * @return 변경 후 아동 상세 프로필
   * @throws BusinessException 아동을 변경할 수 없거나 변경 생년월일이 허용 나이 범위를 벗어난 경우
   */
  @Transactional
  public ChildDetailResponse update(Long guardianUserId, Long childId, UpdateChildRequest request) {
    if (!childUpdateRepository.lockAccessibleChild(guardianUserId, childId)) {
      throw new BusinessException(ChildErrorCode.CHILD_NOT_FOUND);
    }
    validateAge(request.birthDate());

    LocalDateTime now = LocalDateTime.now(clock);
    childUpdateRepository.updateProfile(
        childId, request.nickname(), request.birthDate(), null, request.questionDifficulty(), now);
    if (request.preferredCharacterSpecified()) {
      childUpdateRepository.updatePreferredCharacter(childId, request.preferredCharacter(), now);
    }
    // ⚠️ null 도 유효한 값이다. "고르지 않을래요"를 고른 것과 요청에 안 담은 것은 다르고,
    //    specified 로 그 둘을 가른다 (S15P11B209-1010 v2).
    if (request.educationStageSpecified()) {
      childUpdateRepository.updateEducationStage(childId, request.educationStage(), now);
    }
    if (request.profileImageFileIdSpecified()) {
      String profileImageUrl =
          profileImageLinkService.replace(guardianUserId, childId, request.profileImageFileId());
      childUpdateRepository.updateProfileImageUrl(childId, profileImageUrl, now);
    }
    if (request.relationshipType() != null) {
      childUpdateRepository.updateRelationship(guardianUserId, childId, request.relationshipType());
    }
    if (request.responseModes() != null) {
      List<ResponseMode> distinctModes = List.copyOf(new LinkedHashSet<>(request.responseModes()));
      childUpdateRepository.replaceResponseModes(childId, distinctModes);
    }
    return childQueryService.getChild(guardianUserId, childId);
  }

  private void validateAge(LocalDate birthDate) {
    if (birthDate == null) {
      return;
    }
    int age = Period.between(birthDate, LocalDate.now(clock)).getYears();
    if (age < MINIMUM_AGE || age > MAXIMUM_AGE) {
      throw new BusinessException(ChildErrorCode.CHILD_AGE_OUT_OF_RANGE);
    }
  }
}
