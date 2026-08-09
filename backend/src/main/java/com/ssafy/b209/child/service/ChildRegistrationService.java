package com.ssafy.b209.child.service;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.ResponseMode;
import com.ssafy.b209.child.dto.request.RegisterChildRequest;
import com.ssafy.b209.child.dto.response.ChildRegistrationResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildRegistrationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Period;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자가 요청한 아동 프로필을 등록하고 등록 보호자와의 관계와 응답 방식을 함께 저장한다.
 *
 * <p>등록일 기준 만 나이 범위를 검증하고 중복된 응답 방식은 첫 순서를 유지해 제거한다. 프로필 이미지 연결은 사전 업로드 기반이 마련되기 전까지 저장하지 않는다.
 */
@Service
public class ChildRegistrationService {

  private static final int MINIMUM_AGE = 4;
  private static final int MAXIMUM_AGE = 12;

  private final ChildRegistrationRepository childRegistrationRepository;
  private final ChildProfileImageLinkService profileImageLinkService;
  private final Clock clock;

  /**
   * 운영 시각을 기준으로 아동 등록 서비스를 생성한다.
   *
   * @param childRegistrationRepository 아동 프로필과 관계, 응답 방식을 저장할 저장소
   */
  @Autowired
  public ChildRegistrationService(
      ChildRegistrationRepository childRegistrationRepository,
      ChildProfileImageLinkService profileImageLinkService) {
    this(childRegistrationRepository, profileImageLinkService, Clock.systemUTC());
  }

  ChildRegistrationService(ChildRegistrationRepository childRegistrationRepository, Clock clock) {
    this(childRegistrationRepository, null, clock);
  }

  ChildRegistrationService(
      ChildRegistrationRepository childRegistrationRepository,
      ChildProfileImageLinkService profileImageLinkService,
      Clock clock) {
    this.childRegistrationRepository = childRegistrationRepository;
    this.profileImageLinkService = profileImageLinkService;
    this.clock = clock;
  }

  /**
   * 요청 보호자 소유의 새 아동 프로필을 등록한다.
   *
   * @param guardianUserId 등록을 요청한 보호자 사용자 식별자
   * @param request 등록할 아동 프로필 정보
   * @return 생성된 아동 프로필과 등록 보호자와의 관계
   * @throws BusinessException 등록일 기준 만 나이가 허용 범위를 벗어난 경우
   */
  @Transactional
  public ChildRegistrationResponse register(Long guardianUserId, RegisterChildRequest request) {
    LocalDate today = LocalDate.now(clock);
    int age = Period.between(request.birthDate(), today).getYears();
    if (age < MINIMUM_AGE || age > MAXIMUM_AGE) {
      throw new BusinessException(ChildErrorCode.CHILD_AGE_OUT_OF_RANGE);
    }

    List<ResponseMode> responseModes = distinctInOrder(request.responseModes());
    LocalDateTime now = LocalDateTime.now(clock);

    long childId =
        childRegistrationRepository.insertChild(
            request.nickname(),
            request.birthDate(),
            request.questionDifficulty().name(),
            request.preferredCharacter(),
            null,
            request.educationStage() == null ? null : request.educationStage().name(),
            now);
    childRegistrationRepository.insertGuardianRelation(
        guardianUserId, childId, request.relationshipType().name());
    childRegistrationRepository.insertResponseModes(
        childId, responseModes.stream().map(Enum::name).toList());
    String profileImageUrl = null;
    if (request.profileImageFileId() != null) {
      profileImageUrl =
          profileImageLinkService.attach(guardianUserId, childId, request.profileImageFileId());
      childRegistrationRepository.updateProfileImageUrl(childId, profileImageUrl, now);
    }

    return new ChildRegistrationResponse(
        childId,
        request.nickname(),
        request.birthDate(),
        age,
        request.relationshipType(),
        request.preferredCharacter(),
        request.questionDifficulty(),
        responseModes,
        ChildTutorialStatus.NOT_STARTED,
        ChildProfileStatus.ACTIVE,
        profileImageUrl,
        now.toInstant(ZoneOffset.UTC));
  }

  private List<ResponseMode> distinctInOrder(List<ResponseMode> responseModes) {
    return new ArrayList<>(new LinkedHashSet<>(responseModes));
  }
}
