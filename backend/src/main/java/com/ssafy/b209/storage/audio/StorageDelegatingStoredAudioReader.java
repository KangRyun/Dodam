package com.ssafy.b209.storage.audio;

import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Locale;
import java.util.Objects;

/**
 * 설정된 {@link AudioStorage}로 보관 음성을 읽어 내부 STT 요청에 전달하는 구현체다(S15P11B209-723).
 *
 * <p>{@code STORAGE_MODE=s3}에서 쓰기는 {@code S3AudioStorage}로 가는데 읽기는 {@link
 * LocalStoredAudioReader}뿐이어서, STT가 로컬 파일 시스템을 뒤지다 매번 실패했다. 업로드는 201로 성공하고 STT만 즉시 FAILED가 되는
 * 증상이었다. 저장에 쓴 경계로 읽으면 모드가 갈라져도 같은 위치를 본다.
 *
 * <p>S3 Client를 직접 다루지 않는다. Key 검증·Prefix 결합·404 판정은 이미 {@code AudioStorage} 구현이 하고 있어 그대로 위임한다.
 */
public class StorageDelegatingStoredAudioReader implements StoredAudioReader {

  private final AudioStorage audioStorage;

  /**
   * 보관 음성을 읽을 Storage 경계를 주입받는다.
   *
   * @param audioStorage 현재 저장 모드에 맞게 등록된 음성 Storage
   */
  public StorageDelegatingStoredAudioReader(AudioStorage audioStorage) {
    this.audioStorage = Objects.requireNonNull(audioStorage, "audioStorage must not be null");
  }

  /**
   * {@inheritDoc}
   *
   * <p>Storage가 던지는 실패 사유(Key 불량·객체 부재·조회 실패)는 STT 관점의 단일 사유로 좁힌다. 대화 화면에는 "음성을 쓸 수 없다"만 필요하고 내부 저장
   * 구조를 드러낼 이유가 없다.
   */
  @Override
  public OpenedAudio open(String storageKey) {
    try {
      StoredAudioContent content = audioStorage.read(storageKey);
      return new OpenedAudio(content.inputStream(), transferFilename(storageKey));
    } catch (BusinessException exception) {
      throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE, exception);
    }
  }

  /**
   * 내부 multipart 전송에만 쓰는 비식별 파일명을 만든다.
   *
   * <p>{@link LocalStoredAudioReader}와 같은 규칙이다. AI 서버가 확장자로 음성 형식을 판별하므로 확장자는 유지하고, 원본 업로드 파일명과 저장
   * 경로는 노출하지 않는다.
   *
   * @param storageKey DB에 저장된 음성 key
   * @return {@code voice.<확장자>} 형태의 전송 파일명
   */
  private String transferFilename(String storageKey) {
    int dot = storageKey == null ? -1 : storageKey.lastIndexOf('.');
    String extension = dot < 0 ? "bin" : storageKey.substring(dot + 1).toLowerCase(Locale.ROOT);
    return "voice." + extension.replaceAll("[^a-z0-9]", "");
  }
}
