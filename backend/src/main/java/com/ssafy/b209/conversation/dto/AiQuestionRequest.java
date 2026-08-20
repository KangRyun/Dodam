package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.List;

/** Spring Boot에서 FastAPI로 보내는 목표 내부 질문 생성 요청 DTO다. */
public record AiQuestionRequest(
    Long conversationId,
    Long drawingSessionId,
    Long basisAnalysisId,
    int childAge,
    QuestionDifficulty difficulty,
    List<ResponseMode> allowedResponseModes,
    int currentQuestionCount,
    int maxQuestionCount,
    List<DetectedObject> detectedObjects,
    /**
     * 그림 서술(VLM) — 분석에서 만든 2~4문장 한국어 관찰 서술이다(S15P11B209-704).
     *
     * <p>출처는 {@code analysis_observation_results.overall_summary}이며 {@code basisAnalysisId}로 찾는다.
     * 객체 이름 목록만으로는 색·표정·구도를 근거로 한 질문이 나올 수 없어 함께 보낸다.
     *
     * <p>⚠️ 선택 필드다. 분석이 없거나 서술 생성이 실패했으면 {@code null}이고, 이때 AI는 기존 객체 기반 질문으로 그대로 동작한다.
     */
    String drawingDescription,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion,
    /**
     * 서버가 확정한 그림 활동 유형이다(S15P11B209-712).
     *
     * <p>{@code "HTP"} 또는 {@code "ART_DIARY"}이며, HTP 주제 확정에 실패하면 {@code null}이다. FE 입력이 아니라 저장된 세션
     * 관계에서 서버가 결정한다.
     */
    String activityType,
    /**
     * 서버가 확정한 HTP 그림 주제다(S15P11B209-712).
     *
     * <p>{@code "HOUSE"}, {@code "TREE"}, {@code "PERSON"} 중 하나이며, 그림일기이거나 주제 확정에 실패하면 {@code
     * null}이다.
     */
    String drawingSubject,
    /**
     * 이 대화에서 이미 질문한 대상 객체 Code 목록이다(S15P11B209-712).
     *
     * <p>대화 전체 메시지에서 중복 없이 모은 값이며, 대상이 없으면 빈 리스트다.
     */
    List<String> askedObjectCodes,
    /**
     * 같은 HTP 활동의 앞 주제에서 아이가 들려준 이야기다 (S15P11B209-989).
     *
     * <p>주제마다 대화 세션이 따로 열려 다음 주제는 앞 주제의 발화를 모른다 — 그 단절을 잇는
     * 압축 재료다. 질문은 싣지 않고 아이 답만 싣는다. 첫 주제·그림일기는 빈 목록이다.
     */
    List<PreviousSubjectNote> previousSubjectNotes,
    /**
     * 이 턴을 아이 발화가 아니라 <b>새 그림이 촉발했는지</b> 여부다 (끝난 그림일기 대화의 재개 턴).
     *
     * <p>재개 턴에서 AI는 대화 이력을 처음부터 다시 읽는데, 거기엔 상한 도달로 <b>처리되지 못한 채 남은 마지막 답</b>이 그대로 들어 있다. 그것을 지금 한
     * 대답으로 읽으면 옛 "그만할래"에 맺음말과 종료 확인 신호({@code confirmedStopTarget})를 돌려주고, FE는 그 신호를 받아 방금 다시 연 대화를
     * 즉시 닫는다(실측: 재개 1초 뒤 종료). 아이가 그림을 더 그렸다는 사실 자체가 이전 종료 의사를 뒤집는 행동이므로, 재개 턴에서는 묵은 의사를 재생하지 않도록
     * AI에 알린다.
     *
     * <p>⚠️ "재개가 허용됐다"와 같은 말이 아니다. 재개 가능한 상태에서도 아이가 방금 답을 남긴 턴이면 {@code false}다 — 그 턴을 부른 것은 그림이
     * 아니라 아이의 말이고, 켜 두면 AI가 방금 들어온 진짜 "그만할래"를 묵은 의사로 흘려버린다. 조합 조건은 {@code
     * ConversationQuestionService.resumedByNewDrawing}에 있다.
     *
     * <p>AI 쪽(Python)은 {@code resumed_by_new_drawing}으로 받으며 기본값은 {@code false}다. 일반 진행 중 대화도 {@code
     * false}다.
     */
    boolean resumedByNewDrawing) {

  /**
   * 앞 주제 하나의 노트다 (S15P11B209-989).
   *
   * @param drawingSubject 앞 주제 이름({@code HOUSE|TREE|PERSON})
   * @param childUtterances 그 주제 대화에서 아이가 답한 텍스트 목록(대화 순서)
   */
  public record PreviousSubjectNote(String drawingSubject, List<String> childUtterances) {}
}
