package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportMessageConfirmationView;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 조회에서 메시지의 음성 인식 확인 필요 여부를 배치로 읽는 저장소다 (S15P11B209-902). */
public interface ReportMessageConfirmationViewRepository
    extends JpaRepository<ReportMessageConfirmationView, Long> {

  /**
   * 메시지 식별자 목록으로 확인 필요 여부를 한 번에 조회한다.
   *
   * <p>대표 발화마다 개별 조회하면 발화 수에 비례해 쿼리가 늘어난다.
   *
   * @param ids 조회할 메시지 식별자 목록
   * @return 조회된 메시지 목록
   */
  List<ReportMessageConfirmationView> findByIdIn(Collection<Long> ids);
}
