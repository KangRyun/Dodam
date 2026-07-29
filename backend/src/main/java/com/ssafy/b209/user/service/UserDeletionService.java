package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.child.repository.ChildDeletionRepository;
import com.ssafy.b209.child.service.ChildDeletionService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.exception.UserErrorCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증 사용자의 계정과 그가 혼자 보유한 아동 데이터를 삭제하는 회원 탈퇴 Use Case다.
 *
 * <p><b>2026-07-30 변경 (S15P11B209-728)</b>: 이전에는 {@code users} 행만 지웠다. 그런데 {@code children}에는
 * {@code users}로 향하는 FK가 없어(연결이 {@code guardian_child_relations} 경유), 탈퇴하면 <b>관계만</b> 끊기고 아동
 * 프로필·그림·음성·대화가 소유자 없이 남았다. 고아 상태라 이후 누구도 삭제를 요청할 수 없어, CLAUDE.md 9절의 "회원 탈퇴 시 아동 데이터
 * 함께 삭제" 원칙과 어긋났다.
 *
 * <p>탈퇴 시 데이터 처리는 다음과 같다.
 *
 * <ul>
 *   <li><b>단독 보유 아동과 그 그림·음성·대화</b> — 소프트 삭제 + 스토리지 삭제 큐 적재. 개별 삭제 API와 같은 경로를 재사용한다
 *   <li><b>공동 보유 아동</b> — 관계만 해제(CASCADE). 다른 보호자의 데이터를 지울 수는 없다
 *   <li><b>인증 계정·토큰·알림·좋아요</b> — FK CASCADE로 함께 삭제
 *   <li><b>커뮤니티 글·댓글·감사 로그</b> — SET NULL로 비식별화. 대화 맥락은 남기되 작성자를 지운다
 *   <li><b>동의 증빙</b> — 보존. 법적 보존 대상이다(가드레일 9절)
 * </ul>
 */
@Service
public class UserDeletionService {

  private static final String CONFIRMATION = "DELETE";

  private final UserRepository userRepository;
  private final ChildDeletionService childDeletionService;
  private final ChildDeletionRepository childDeletionRepository;

  /**
   * 회원 탈퇴 서비스를 구성한다.
   *
   * @param userRepository 사용자 존재 확인과 hard delete를 수행할 저장소
   * @param childDeletionService 아동 삭제 정책(소프트 삭제 + 스토리지 큐)을 가진 서비스
   * @param childDeletionRepository 전문가 프로필 존재 확인용 저장소
   */
  public UserDeletionService(
      UserRepository userRepository,
      ChildDeletionService childDeletionService,
      ChildDeletionRepository childDeletionRepository) {
    this.userRepository = userRepository;
    this.childDeletionService = childDeletionService;
    this.childDeletionRepository = childDeletionRepository;
  }

  /**
   * 확인 문자열을 검증하고, 아동 데이터를 먼저 정리한 뒤 사용자를 삭제한다.
   *
   * <p><b>아동 삭제가 먼저다.</b> 사용자를 먼저 지우면 {@code guardian_child_relations}가 CASCADE로 사라져 "이 보호자의
   * 아동"을 더는 찾을 수 없다. 순서가 바뀌면 오류 없이 조용히 아무것도 지우지 못한다.
   *
   * <p>같은 트랜잭션에서 처리한다 — 아동만 삭제되고 사용자가 남거나 그 반대가 되면 복구가 어렵다.
   *
   * @param userId Access Token으로 인증된 사용자 ID
   * @param request 탈퇴 확인 요청
   * @throws BusinessException 확인 문자열이 다르거나, 사용자가 없거나, 전문가 프로필이 있는 경우
   */
  @Transactional
  public void delete(Long userId, DeleteUserRequest request) {
    if (!CONFIRMATION.equals(request.confirmation())) {
      throw new BusinessException(UserErrorCode.WITHDRAWAL_CONFIRMATION_MISMATCH);
    }
    if (!userRepository.existsById(userId)) {
      throw new BusinessException(UserErrorCode.USER_NOT_FOUND);
    }
    // expert_profiles.users_id 가 ON DELETE RESTRICT 다. 확인하지 않고 지우면 DB 제약 위반이 500 으로 샌다.
    //   전문가 프로필은 자격 심사 이력(검증 상태·경력)을 담고 있어 함께 지울지가 정책 결정 사항이라
    //   임의로 삭제하지 않고, 원인을 알 수 있는 4xx 로 돌려준다.
    if (childDeletionRepository.hasExpertProfile(userId)) {
      throw new BusinessException(UserErrorCode.WITHDRAWAL_BLOCKED_BY_EXPERT_PROFILE);
    }
    childDeletionService.deleteAllSolelyOwnedBy(userId);
    userRepository.deleteById(userId);
  }
}
