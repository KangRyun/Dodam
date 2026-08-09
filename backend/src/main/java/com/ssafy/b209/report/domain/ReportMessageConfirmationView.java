package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * 리포트 조회에서 대화 메시지의 음성 인식 확인 필요 여부와 음성 재생 참조 존재 여부를 읽는 읽기 전용 프로젝션이다.
 *
 * <p>{@code report_key_conversations}에는 이 값이 없어 원 메시지에서 읽어야 한다. 종전에는 응답의 {@code
 * sttNeedsConfirmation}에 리터럴 {@code false}를 넘겼는데, 그러면 "미확정 발화는 근거·대표 발화에서 제외한다"는 규칙(계약 §4-4)이 조건
 * 자체가 참이 되지 않아 조용히 무효가 된다.
 *
 * <p>발화 원문은 읽지 않는다 — 필요한 것은 플래그뿐이고, 원문을 이 경로로 끌어오면 로그·예외에 섞일 위험만 늘어난다.
 */
@Entity
@Table(name = "conversation_messages")
public class ReportMessageConfirmationView {

  @Id private Long id;

  @Column(name = "needs_guardian_confirmation", nullable = false)
  private boolean needsGuardianConfirmation;

  @Column(name = "message_type", nullable = false)
  private String messageType;

  @Column(name = "audio_storage_key")
  private String audioStorageKey;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportMessageConfirmationView() {}

  /**
   * @return 메시지 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 보호자 확인이 필요한 음성 인식 결과면 {@code true}
   */
  public boolean isNeedsGuardianConfirmation() {
    return needsGuardianConfirmation;
  }

  /**
   * 현재 메시지가 아이 음성 답변이고 원본 음성 참조가 남아 있는지 확인한다.
   *
   * <p>Storage Key 자체는 외부에 반환하지 않으며, 호출자는 이 결과로 인증 Proxy 경로 노출 여부만 정한다.
   *
   * @return 음성 재생을 시도할 수 있으면 {@code true}
   */
  public boolean hasPlayableVoiceAudioReference() {
    return "VOICE_ANSWER".equals(messageType)
        && audioStorageKey != null
        && !audioStorageKey.isBlank();
  }
}
