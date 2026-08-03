package com.ssafy.b209.expert.repository;

import com.ssafy.b209.expert.domain.ExpertCredential;
import org.springframework.data.jpa.repository.JpaRepository;

/** 전문가 자격과 연결 증빙 파일을 함께 영속화하는 저장소다. */
public interface ExpertCredentialRepository extends JpaRepository<ExpertCredential, Long> {}
