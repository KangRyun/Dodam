package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.QuestionOption;
import java.util.List;

/** 저장 직전에 확정된 AI 또는 템플릿 질문이다. */
record QuestionCandidate(
    String questionText,
    List<QuestionOption> options,
    DetectedObject targetObject,
    Long questionTemplateId,
    boolean fallbackUsed) {}
