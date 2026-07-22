package com.ssafy.b209.consent.repository;

import com.ssafy.b209.consent.domain.ConsentRecord;
import org.springframework.data.jpa.repository.JpaRepository;

/** 현재 상태를 덮어쓰지 않고 동의·철회 이력을 append하는 저장소다. */
public interface ConsentRecordRepository extends JpaRepository<ConsentRecord, Long> {}
