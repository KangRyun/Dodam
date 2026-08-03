package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.dto.UserBlockCommandResult;
import com.ssafy.b209.community.dto.UserBlockResponse;
import com.ssafy.b209.community.exception.CommunitySafetyErrorCode;
import com.ssafy.b209.community.repository.CommunityUserBlockRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.exception.UserErrorCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 현재 사용자의 커뮤니티 차단 관계를 상태 기반 멱등 연산으로 관리한다. */
@Service
public class CommunityUserBlockService {

  private final CurrentAuthenticatedUserResolver userResolver;
  private final UserRepository userRepository;
  private final CommunityUserBlockRepository blockRepository;

  /** 차단 작업에 필요한 인증 경계와 사용자·차단 저장소를 주입한다. */
  public CommunityUserBlockService(
      CurrentAuthenticatedUserResolver userResolver,
      UserRepository userRepository,
      CommunityUserBlockRepository blockRepository) {
    this.userResolver = userResolver;
    this.userRepository = userRepository;
    this.blockRepository = blockRepository;
  }

  /**
   * 대상 사용자를 차단하며 이미 차단된 경우 현재 상태를 그대로 반환한다.
   *
   * @param blockedUserId 차단 대상 사용자 ID
   * @return 차단 상태와 신규 생성 여부
   * @throws BusinessException 자기 자신이거나 존재하지 않는 사용자를 차단한 경우
   */
  @Transactional
  public UserBlockCommandResult blockUser(Long blockedUserId) {
    Long blockerUserId = userResolver.requireUserId();
    validateTarget(blockerUserId, blockedUserId);
    boolean created = blockRepository.insertIfAbsent(blockerUserId, blockedUserId);
    return new UserBlockCommandResult(new UserBlockResponse(blockedUserId, true), created);
  }

  /**
   * 대상 사용자 차단을 해제하며 관계가 없어도 성공한다.
   *
   * @param blockedUserId 차단 해제 대상 사용자 ID
   * @throws BusinessException 자기 자신 또는 존재하지 않는 사용자를 지정한 경우
   */
  @Transactional
  public void unblockUser(Long blockedUserId) {
    Long blockerUserId = userResolver.requireUserId();
    validateTarget(blockerUserId, blockedUserId);
    blockRepository.delete(blockerUserId, blockedUserId);
  }

  private void validateTarget(Long blockerUserId, Long blockedUserId) {
    if (blockerUserId.equals(blockedUserId)) {
      throw new BusinessException(CommunitySafetyErrorCode.USER_BLOCK_SELF_NOT_ALLOWED);
    }
    User target =
        userRepository
            .findById(blockedUserId)
            .orElseThrow(() -> new BusinessException(UserErrorCode.USER_NOT_FOUND));
    if (target.getAccountStatus() == AccountStatus.DELETED) {
      throw new BusinessException(UserErrorCode.USER_NOT_FOUND);
    }
  }
}
