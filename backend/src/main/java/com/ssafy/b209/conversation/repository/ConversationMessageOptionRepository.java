package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessageOption;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConversationMessageOptionRepository
    extends JpaRepository<ConversationMessageOption, Long> {}
