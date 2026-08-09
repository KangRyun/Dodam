package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDrawingTypeView;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 그림 활동 유형을 읽는 저장소다. */
public interface ReportDrawingTypeViewRepository
    extends JpaRepository<ReportDrawingTypeView, Long> {}
