package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportKeyConversation;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 주요 대화 Snapshot의 저장을 담당한다. */
public interface ReportKeyConversationRepository
    extends JpaRepository<ReportKeyConversation, Long> {}
