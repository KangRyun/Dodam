package com.ssafy.b209.child.repository;

import java.time.LocalDate;

/**
 * 아동 목록 조회에 필요한 아동 프로필과 보호자 관계의 읽기 전용 Projection이다.
 *
 * <p>보호자 소유권 조건을 적용한 Repository Query 결과만 담으며 API 응답 조립은 Service가 담당한다.
 */
public interface ChildSummaryProjection {

  /**
   * 아동 식별자를 반환한다.
   *
   * @return 아동 식별자
   */
  Long getChildId();

  /**
   * 아동 별칭을 반환한다.
   *
   * @return 아동 별칭
   */
  String getNickname();

  /**
   * 만 나이를 계산할 생년월일을 반환한다.
   *
   * @return 만 나이 계산에 사용할 생년월일
   */
  LocalDate getBirthDate();

  /**
   * 아동 프로필 이미지 URL을 반환한다.
   *
   * @return 프로필 이미지 URL 또는 {@code null}
   */
  String getProfileImageUrl();

  /**
   * 대화 질문 난이도의 DB 문자열을 반환한다.
   *
   * @return 질문 난이도 Enum 이름
   */
  String getQuestionDifficulty();

  /**
   * Tutorial 진행 상태의 DB 문자열을 반환한다.
   *
   * @return Tutorial 상태 Enum 이름
   */
  String getTutorialStatus();

  /**
   * 아동 프로필 상태의 DB 문자열을 반환한다.
   *
   * @return 프로필 상태 Enum 이름
   */
  String getProfileStatus();

  /**
   * 현재 조회 보호자와 아동 사이의 관계 유형을 반환한다.
   *
   * @return 조회 보호자와 아동의 관계 유형
   */
  String getRelationshipType();
}
