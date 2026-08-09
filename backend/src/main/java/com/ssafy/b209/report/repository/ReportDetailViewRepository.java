package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDetailView;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 리포트 헤더를 읽는 저장소다. */
public interface ReportDetailViewRepository extends JpaRepository<ReportDetailView, Long> {}
