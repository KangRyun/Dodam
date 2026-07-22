package com.ssafy.b209.auth.repository;

import com.ssafy.b209.auth.domain.AuthAccount;
import com.ssafy.b209.auth.domain.AuthProvider;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

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
}
