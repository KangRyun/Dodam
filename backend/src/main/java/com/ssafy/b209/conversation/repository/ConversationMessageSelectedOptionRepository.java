package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import org.springframework.data.jpa.repository.JpaRepository;

/** 아동 선택 응답 행을 저장하는 저장소다. */
public interface ConversationMessageSelectedOptionRepository
    extends JpaRepository<ConversationMessageSelectedOption, Long> {}
