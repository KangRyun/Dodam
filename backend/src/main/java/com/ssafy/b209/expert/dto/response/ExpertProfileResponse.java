package com.ssafy.b209.expert.dto.response;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import java.util.List;

/**
 * 전문가 프로필 생성 결과와 공개 조회에 공통으로 사용할 핵심 필드다.
 *
 * @param expertId 전문가 프로필 식별자
 * @param displayName 공개 표시 이름
 * @param profileImageUrl 프로필 이미지 URL
 * @param organization 소속 기관
 * @param positionTitle 직책
 * @param careerYears 경력 연수
 * @param specialties 전문 분야 코드 목록
 * @param targetAgeMin 상담 대상 최소 연령
 * @param targetAgeMax 상담 대상 최대 연령
 * @param introduction 공개 소개 문구
 * @param consultationAvailable 상담 가능 여부
 * @param verificationStatus 운영 검증 상태
 * @param workplace 공개 근무지
 * @param followerCount 팔로워 수
 * @param followedByMe 현재 요청자의 팔로우 여부
 */
public record ExpertProfileResponse(
    Long expertId,
    String displayName,
    String profileImageUrl,
    String organization,
    String positionTitle,
    int careerYears,
    List<String> specialties,
    Integer targetAgeMin,
    Integer targetAgeMax,
    String introduction,
    boolean consultationAvailable,
    ExpertVerificationStatus verificationStatus,
    String workplace,
    long followerCount,
    boolean followedByMe) {}
