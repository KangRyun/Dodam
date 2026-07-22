package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.AiQuestionTemplate;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 활성 기본 질문 템플릿 조회 경계다. */
public interface AiQuestionTemplateRepository extends JpaRepository<AiQuestionTemplate, Long> {

  Optional<AiQuestionTemplate> findFirstByTemplateTypeAndActiveTrueOrderByIdAsc(
      String templateType);
}
