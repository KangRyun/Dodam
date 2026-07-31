package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.RefreshTokenSessionStore;
import com.ssafy.b209.child.repository.ChildDeletionRepository;
import com.ssafy.b209.child.service.ChildDeletionService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증 사용자를 삭제 상태로 전환하고 그가 보유한 아동 데이터를 정리하는 회원 탈퇴 Use Case다.
 *
 * <p><b>2026-07-30 변경 (S15P11B209-728)</b>: 이전에는 {@code users} 행만 지웠다. 그런데 {@code children}에는
 * {@code users}로 향하는 FK가 없어(연결이 {@code guardian_child_relations} 경유), 탈퇴하면 <b>관계만</b> 끊기고 아동
 * 프로필·그림·음성·대화가 소유자 없이 남았다. 고아 상태라 이후 누구도 삭제를 요청할 수 없어, CLAUDE.md 9절의 "회원 탈퇴 시 아동 데이터 함께 삭제" 원칙과
 * 어긋났다.
 *
 * <p>탈퇴 시 데이터 처리는 다음과 같다.
 *
 * <ul>
 *   <li><b>단독 보유 아동과 그 그림·음성·대화</b> — 소프트 삭제 + 스토리지 삭제 큐 적재. 개별 삭제 API와 같은 경로를 재사용한다
 *   <li><b>공동 보유 아동</b> — 관계만 해제(CASCADE). 다른 보호자의 데이터를 지울 수는 없다
 *   <li><b>사용자 행</b> — {@code account_status=DELETED}, {@code deleted_at} 기록. 물리 삭제하지 않는다
 *   <li><b>Access·Refresh Token</b> — Access Token은 사용자 상태 확인으로 차단하고, Refresh family는 모두 폐기
 *   <li><b>인증 계정·동의 증빙·전문가 프로필</b> — 행을 유지한다. 물리 삭제와 보존 만료 purge는 이번 범위가 아니다
 *   <li><b>동의 증빙</b> — 보존. 법적 보존 대상이다(가드레일 9절)
 * </ul>
 */
@Service
public class UserDeletionService {

  private static final String CONFIRMATION = "DELETE";

  private final UserRepository userRepository;
  private final ChildDeletionService childDeletionService;
  private final ChildDeletionRepository childDeletionRepository;
  private final RefreshTokenSessionStore refreshTokenSessionStore;
  private final Clock clock;

  /**
   * 회원 탈퇴 서비스를 구성한다.
   *
   * @param userRepository 사용자 상태 전이를 수행할 저장소
   * @param childDeletionService 아동 삭제 정책(소프트 삭제 + 스토리지 큐)을 가진 서비스
   * @param childDeletionRepository 보호자-아동 관계 해제 저장소
   * @param refreshTokenSessionStore 사용자 전체 Refresh Token family 폐기 저장소
   */
  @Autowired
  public UserDeletionService(
      UserRepository userRepository,
      ChildDeletionService childDeletionService,
      ChildDeletionRepository childDeletionRepository,
      RefreshTokenSessionStore refreshTokenSessionStore) {
    this(
        userRepository,
        childDeletionService,
        childDeletionRepository,
        refreshTokenSessionStore,
        Clock.systemUTC());
  }

  UserDeletionService(
      UserRepository userRepository,
      ChildDeletionService childDeletionService,
      ChildDeletionRepository childDeletionRepository,
      RefreshTokenSessionStore refreshTokenSessionStore,
      Clock clock) {
    this.userRepository = userRepository;
    this.childDeletionService = childDeletionService;
    this.childDeletionRepository = childDeletionRepository;
    this.refreshTokenSessionStore = refreshTokenSessionStore;
    this.clock = clock;
  }

  /**
   * 확인 문자열을 검증하고, 아동 데이터를 먼저 정리한 뒤 사용자를 삭제 상태로 전환한다.
   *
   * <p><b>아동 처리와 관계 해제가 먼저다.</b> 단독 보유 여부는 보호자 관계를 기준으로 판정하므로, 관계를 먼저 끊으면 삭제 대상이 사라진다.
   *
   * <p>같은 트랜잭션에서 처리한다 — 아동만 삭제되고 사용자가 남거나 그 반대가 되면 복구가 어렵다.
   *
   * @param userId Access Token으로 인증된 사용자 ID
   * @param request 탈퇴 확인 요청
   * @throws BusinessException 확인 문자열이 다르거나 사용자가 존재하지 않는 경우
   */
  @Transactional
  public void delete(Long userId, DeleteUserRequest request) {
    if (!CONFIRMATION.equals(request.confirmation())) {
      throw new BusinessException(UserErrorCode.WITHDRAWAL_CONFIRMATION_MISMATCH);
    }
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(UserErrorCode.USER_NOT_FOUND));
    if (user.getAccountStatus() == AccountStatus.DELETED) {
      throw new BusinessException(UserErrorCode.USER_NOT_FOUND);
    }
    childDeletionService.deleteAllSolelyOwnedBy(userId);
    childDeletionRepository.deleteGuardianRelations(userId);
    user.markDeleted(LocalDateTime.now(clock));
    refreshTokenSessionStore.revokeAll(userId);
  }
}
