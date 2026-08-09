package com.ssafy.b209.user.repository;

import com.ssafy.b209.user.domain.DataExportJob;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 데이터 내보내기 작업을 저장한다. */
public interface DataExportJobRepository extends JpaRepository<DataExportJob, Long> {

  Optional<DataExportJob> findByIdAndUserId(Long id, Long userId);
}
