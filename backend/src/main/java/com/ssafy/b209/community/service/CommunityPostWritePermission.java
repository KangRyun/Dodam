package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.community.domain.PostType;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.global.exception.BusinessException;

/**
 * 게시글 유형별 작성·수정 권한을 사용자 역할로 판정하는 규칙이다.
 *
 * <p>작성과 수정(유형 변경 시)이 같은 규칙을 공유하도록 중복 없이 한곳에서 관리한다. 공지는 관리자만, 전문가 자료 3종은 전문가 또는 관리자만 허용하고, 나머지 유형은
 * 인증된 모든 역할이 허용된다.
 */
final class CommunityPostWritePermission {

  private CommunityPostWritePermission() {}

  /**
   * 주어진 역할이 해당 게시글 유형을 작성·수정할 수 있는지 검증한다.
   *
   * @param postType 확인할 게시글 유형
   * @param role 현재 사용자 역할
   * @throws BusinessException 해당 유형을 작성·수정할 권한이 없는 경우
   */
  static void verify(PostType postType, UserRole role) {
    boolean allowed =
        switch (postType) {
          case NOTICE -> role == UserRole.ADMIN;
          case EXPERT_COLUMN, ART_RESOURCE, DRAWING_GUIDE ->
              role == UserRole.EXPERT || role == UserRole.ADMIN;
          case GUARDIAN_STORY, ACTIVITY_REVIEW, EXPERT_QNA -> true;
        };
    if (!allowed) {
      throw new BusinessException(CommunityErrorCode.POST_TYPE_NOT_ALLOWED);
    }
  }
}
