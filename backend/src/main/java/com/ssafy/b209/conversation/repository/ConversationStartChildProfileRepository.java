package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationStartChildProfile;
import org.springframework.data.jpa.repository.JpaRepository;

/** 대화 시작에 필요한 아동 난이도 Snapshot을 조회하는 저장소다. */
public interface ConversationStartChildProfileRepository
    extends JpaRepository<ConversationStartChildProfile, Long> {}
