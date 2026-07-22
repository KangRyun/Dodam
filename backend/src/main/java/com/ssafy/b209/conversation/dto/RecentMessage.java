package com.ssafy.b209.conversation.dto;

/** 최소 대화 문맥이다. 텍스트는 로그에 남기지 않는다. */
public record RecentMessage(Long messageId, String senderType, String messageType, String text) {}
