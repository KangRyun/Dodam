package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportActivityNote;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 활동 주의사항의 저장을 담당한다. */
public interface ReportActivityNoteRepository extends JpaRepository<ReportActivityNote, Long> {}
