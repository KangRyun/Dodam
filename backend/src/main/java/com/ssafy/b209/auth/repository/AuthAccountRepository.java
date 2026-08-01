package com.ssafy.b209.auth.repository;

import com.ssafy.b209.auth.domain.AuthAccount;
import com.ssafy.b209.auth.domain.AuthProvider;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** Provider의 불변 사용자 식별자로 서비스 인증 계정을 조회하고 저장한다. */
public interface AuthAccountRepository extends JpaRepository<AuthAccount, Long> {

  /**
   * Provider별 외부 사용자 식별자에 연결된 인증 계정을 조회한다.
   *
   * @param provider OAuth Provider
   * @param providerSubject Provider가 발급한 불변 사용자 식별자
   * @return 연결된 인증 계정, 없으면 빈 값
   */
  Optional<AuthAccount> findByProviderAndProviderSubject(
      AuthProvider provider, String providerSubject);

  /**
   * 사용자의 인증 계정 연결을 모두 물리 삭제한다. 회원 탈퇴 전용이다(S15P11B209-768).
   *
   * <p>탈퇴가 소프트 삭제로 바뀌면서(728) 이 행이 남으면, 위 {@code findByProviderAndProviderSubject}가
   * 재로그인 때 DELETED 사용자를 다시 물어와 같은 소셜 계정으로 재가입이 영영 막힌다. {@code provider_subject}는
   * 개인 식별자이기도 하다 — 탈퇴 후 무기한 보존은 가드레일 9절(수명주기)과도 맞지 않는다.
   *
   * @param userId 탈퇴하는 사용자 ID
   */
  @Modifying
  @Query("delete from AuthAccount a where a.user.id = :userId")
  void deleteAllByUserId(@Param("userId") Long userId);
}
