package com.ssafy.b209.conversation.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.domain.ConversationMessageOption;
import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.OptionAnswerMessage;
import com.ssafy.b209.conversation.dto.OptionAnswerRequest;
import com.ssafy.b209.conversation.dto.OptionAnswerResponse;
import com.ssafy.b209.conversation.dto.SelectedOptionCommand;
import com.ssafy.b209.conversation.exception.OptionAnswerErrorCode;
import com.ssafy.b209.conversation.repository.ConversationMessageOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageSelectedOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.OptionAnswerMessageRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 선택형 답변의 권한·동의·상태 검증과 질문 선택지 Snapshot 대조, OPTION_ANSWER 메시지·선택 응답 저장을 담당한다.
 *
 * <p>음성 답변(288/289)과 동일한 소유권·동의·세션 잠금·순번 기반을 재사용하되, 음성 처리 동의는 요구하지 않고 선택 응답 정규화 테이블에 저장한다.
 */
@Service
public class OptionAnswerService {
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;
  private final OptionAnswerMessageRepository messageRepository;
  private final ConversationMessageOptionRepository optionRepository;
  private final ConversationMessageSelectedOptionRepository selectedOptionRepository;
  private final ObjectMapper objectMapper;
  private final Clock clock;

  /**
   * 선택형 답변 Use Case 의존성을 생성한다.
   *
   * @param conversationSessionRepository 세션 조회·비관 잠금 경계
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param authorizationRepository 보호자 관계·필수 동의 조회 경계
   * @param messageRepository 질문 검증·중복 답변 확인·순번·답변 저장 경계
   * @param optionRepository 질문 선택지 Snapshot 조회 경계
   * @param selectedOptionRepository 선택 응답 저장 경계
   * @param objectMapper 요청 fingerprint 직렬화 도구
   * @param clock 서버 생성 시각 기준
   */
  public OptionAnswerService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository,
      OptionAnswerMessageRepository messageRepository,
      ConversationMessageOptionRepository optionRepository,
      ConversationMessageSelectedOptionRepository selectedOptionRepository,
      ObjectMapper objectMapper,
      Clock clock) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.messageRepository = messageRepository;
    this.optionRepository = optionRepository;
    this.selectedOptionRepository = selectedOptionRepository;
    this.objectMapper = objectMapper;
    this.clock = clock;
  }

  /**
   * 동일 Body 재전송 식별에 쓰는 요청의 SHA-256 fingerprint를 만든다.
   *
   * @param request 검증된 선택형 답변 요청
   * @return 비밀값 없는 고정 길이 fingerprint
   */
  public String fingerprint(OptionAnswerRequest request) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(objectMapper.writeValueAsBytes(request)));
    } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
      throw new BusinessException(OptionAnswerErrorCode.INVALID_REQUEST, exception);
    }
  }

  /**
   * 세션 비관 잠금 안에서 권한·질문·선택지를 검증하고 답변 메시지와 선택 응답을 저장한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 ID
   * @param conversationId URL 대화 세션 ID
   * @param request 검증된 선택형 답변 요청
   * @return 저장된 선택형 답변 결과
   * @throws BusinessException 권한·동의·세션 상태·질문·선택지 검증에 실패하거나 저장이 충돌한 경우
   */
  @Transactional
  public OptionAnswerResponse submit(
      Long guardianUserId, Long conversationId, OptionAnswerRequest request) {
    ConversationSession session =
        conversationSessionRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(() -> new BusinessException(OptionAnswerErrorCode.CONVERSATION_NOT_FOUND));
    validateAccessAndState(guardianUserId, session);

    Long questionMessageId = request.questionMessageId();
    if (!messageRepository.existsQuestion(questionMessageId, conversationId)) {
      throw new BusinessException(OptionAnswerErrorCode.QUESTION_MESSAGE_NOT_FOUND);
    }
    if (messageRepository.existsAnswerForQuestion(conversationId, questionMessageId)) {
      throw new BusinessException(OptionAnswerErrorCode.ANSWER_ALREADY_SUBMITTED);
    }

    List<ConversationMessageOption> matched =
        matchSelectedOptions(questionMessageId, request.selectedOptions());
    String directText = normalizeDirectText(request.directText());
    int nextSequence =
        messageRepository.findMaxMessageSequenceByConversationSessionId(conversationId) + 1;

    try {
      OptionAnswerMessage saved =
          messageRepository.saveAndFlush(
              OptionAnswerMessage.of(
                  conversationId,
                  questionMessageId,
                  nextSequence,
                  directText,
                  LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)));
      List<ConversationMessageSelectedOption> selections = new ArrayList<>();
      short order = 0;
      for (ConversationMessageOption option : matched) {
        selections.add(
            ConversationMessageSelectedOption.of(
                saved.getId(), questionMessageId, option.getId(), option.getLabel(), order));
        order++;
      }
      selectedOptionRepository.saveAll(selections);
      selectedOptionRepository.flush();
      return buildResponse(saved, conversationId, request.selectedOptions(), directText);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(OptionAnswerErrorCode.OPTION_ANSWER_STORAGE_CONFLICT, exception);
    }
  }

  private void validateAccessAndState(Long guardianUserId, ConversationSession session) {
    ConversationStartDrawingSession drawingSession =
        drawingSessionRepository
            .findById(session.getDrawingSessionId())
            .orElseThrow(() -> new BusinessException(OptionAnswerErrorCode.CONVERSATION_NOT_FOUND));
    Long childId = drawingSession.getChildId();
    if (!authorizationRepository.hasGuardianChildRelation(guardianUserId, childId)) {
      throw new BusinessException(OptionAnswerErrorCode.CONVERSATION_ACCESS_DENIED);
    }
    if (!authorizationRepository.hasRequiredConsents(childId)) {
      throw new BusinessException(OptionAnswerErrorCode.CONSENT_REQUIRED);
    }
    if (session.isCompleted()) {
      throw new BusinessException(OptionAnswerErrorCode.CONVERSATION_ALREADY_COMPLETED);
    }
    if (!session.isConversing()) {
      throw new BusinessException(OptionAnswerErrorCode.CONVERSATION_NOT_CONVERSING);
    }
  }

  private List<ConversationMessageOption> matchSelectedOptions(
      Long questionMessageId, List<SelectedOptionCommand> selectedOptions) {
    Map<String, ConversationMessageOption> byOptionKey = new HashMap<>();
    for (ConversationMessageOption option :
        optionRepository.findByConversationMessageId(questionMessageId)) {
      byOptionKey.put(option.getOptionKey(), option);
    }
    Set<String> seenOptionKeys = new HashSet<>();
    List<ConversationMessageOption> matched = new ArrayList<>();
    for (SelectedOptionCommand selected : selectedOptions) {
      if (!seenOptionKeys.add(selected.optionId())) {
        throw new BusinessException(OptionAnswerErrorCode.OPTION_NOT_ALLOWED);
      }
      ConversationMessageOption option = byOptionKey.get(selected.optionId());
      if (option == null
          || !option.getOptionType().equals(selected.type())
          || !option.getOptionValue().equals(selected.value())
          || !option.getLabel().equals(selected.labelSnapshot())) {
        throw new BusinessException(OptionAnswerErrorCode.OPTION_NOT_ALLOWED);
      }
      matched.add(option);
    }
    return matched;
  }

  private String normalizeDirectText(String directText) {
    if (directText == null || directText.isBlank()) {
      return null;
    }
    return directText;
  }

  private OptionAnswerResponse buildResponse(
      OptionAnswerMessage saved,
      Long conversationId,
      List<SelectedOptionCommand> selectedOptions,
      String directText) {
    return new OptionAnswerResponse(
        saved.getId(),
        conversationId,
        saved.getParentMessageId(),
        saved.getMessageSequence(),
        saved.getSenderType(),
        "ANSWER_OPTION",
        List.copyOf(selectedOptions),
        directText,
        saved.getCreatedAt());
  }
}
