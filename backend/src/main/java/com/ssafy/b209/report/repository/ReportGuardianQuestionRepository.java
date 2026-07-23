package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportGuardianQuestion;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 보호자 질문의 저장을 담당한다. */
public interface ReportGuardianQuestionRepository
    extends JpaRepository<ReportGuardianQuestion, Long> {}
