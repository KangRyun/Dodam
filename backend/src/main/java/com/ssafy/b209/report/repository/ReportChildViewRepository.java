package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportChildView;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 표지용 아동 표시명을 조회하는 저장소다 (S15P11B209-960, 875 §2). */
public interface ReportChildViewRepository extends JpaRepository<ReportChildView, Long> {}
