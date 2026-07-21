package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingType;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림 활동 시작 시 선택할 유형을 식별자로 조회하는 저장소다. */
public interface DrawingTypeRepository extends JpaRepository<DrawingType, Long> {}
