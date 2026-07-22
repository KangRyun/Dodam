package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessageTarget;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConversationMessageTargetRepository
    extends JpaRepository<ConversationMessageTarget, Long> {}
