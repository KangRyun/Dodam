package com.ssafy.b209.consent.repository;

import com.ssafy.b209.consent.domain.ConsentTerm;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 동의 요청이 참조하는 버전 약관과 현재 활성 필수 약관을 조회한다. */
public interface ConsentTermRepository extends JpaRepository<ConsentTerm, Long> {

  /**
   * 활성 표시된 약관을 조회한다. 실제 시행 시각은 Service의 동일 기준 시각으로 추가 검증한다.
   *
   * @return 활성 약관 목록
   */
  List<ConsentTerm> findAllByActiveTrue();
}
