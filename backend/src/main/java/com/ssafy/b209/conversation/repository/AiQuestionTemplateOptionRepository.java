package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.AiQuestionTemplateOption;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AiQuestionTemplateOptionRepository
    extends JpaRepository<AiQuestionTemplateOption, Long> {

  List<AiQuestionTemplateOption> findByQuestionTemplateIdOrderByDisplayOrderAsc(
      Long questionTemplateId);
}
