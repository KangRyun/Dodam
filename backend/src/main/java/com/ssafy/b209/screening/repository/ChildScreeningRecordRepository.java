package com.ssafy.b209.screening.repository;

import com.ssafy.b209.screening.domain.ChildScreeningRecord;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 보호자가 옮겨 적은 선별 결과 기록을 담당한다. */
public interface ChildScreeningRecordRepository extends JpaRepository<ChildScreeningRecord, Long> {

  /**
   * 아동의 살아 있는 기록을 최근 실시일 순으로 읽는다.
   *
   * <p>삭제된 기록은 행을 남겨 두지만 조회에서는 빠진다 — 보호자가 지운 의료 기록이 리포트에 계속 보이면 삭제권이 이름뿐이다.
   *
   * @param childId 아동 식별자
   * @return 실시일 내림차순 목록이며 없으면 빈 목록
   */
  List<ChildScreeningRecord> findByChildIdAndDeletedAtIsNullOrderByCompletedAtDesc(Long childId);

  /**
   * 아동에 속한 기록 하나를 읽는다. 다른 아동의 기록 식별자로는 찾히지 않는다.
   *
   * @param id 기록 식별자
   * @param childId 아동 식별자
   * @return 살아 있는 기록이며 없으면 빈 {@link Optional}
   */
  Optional<ChildScreeningRecord> findByIdAndChildIdAndDeletedAtIsNull(Long id, Long childId);
}
