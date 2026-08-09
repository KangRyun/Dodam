package com.ssafy.b209.screening.repository;

import com.ssafy.b209.screening.domain.ChildScreeningRecordDomain;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 선별 결과의 영역별 라벨을 담당한다. */
public interface ChildScreeningRecordDomainRepository
    extends JpaRepository<ChildScreeningRecordDomain, Long> {

  /**
   * 영역별 라벨을 노출 순서대로 읽는다.
   *
   * @param screeningRecordIds 선별 결과 기록 식별자 목록
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ChildScreeningRecordDomain> findByScreeningRecord_IdInOrderByDisplayOrderAsc(
      List<Long> screeningRecordIds);
}
