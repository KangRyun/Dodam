package com.ssafy.b209.infrastructure.ai;

import com.ssafy.b209.storage.audio.OpenedAudio;
import java.util.Objects;
import java.util.function.Supplier;

/**
 * Spring에서 내부 AI STT로 전달할 최소 multipart 입력이다.
 *
 * <p>보호자·아동 식별값, 원본 파일명, 절대 저장 경로는 이 계약에 포함하지 않는다.
 *
 * @param audioSupplier 재시도마다 새로 여는 이미 저장·검증된 음성 공급자
 * @param requestId 동일 호출의 재시도에 유지하는 내부 추적 ID
 */
public record AiSttRequest(Supplier<OpenedAudio> audioSupplier, String requestId) {

  /** 내부 AI multipart를 만들기 전에 null·범위 필수값을 확인한다. */
  public AiSttRequest {
    Objects.requireNonNull(audioSupplier, "audioSupplier must not be null");
    if (requestId == null || requestId.isBlank()) {
      throw new IllegalArgumentException("requestId must not be blank");
    }
  }

  /** 연결·502 재시도마다 처음부터 읽을 새 음성 Stream과 일반 파일명을 연다. */
  public OpenedAudio openAudio() {
    OpenedAudio audio = audioSupplier.get();
    return Objects.requireNonNull(audio, "audioSupplier must not return null");
  }
}
