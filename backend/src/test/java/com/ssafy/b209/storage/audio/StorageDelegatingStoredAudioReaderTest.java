package com.ssafy.b209.storage.audio;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class StorageDelegatingStoredAudioReaderTest {

  private static final String STORAGE_KEY = "2026/07/29/44444444-4444-4444-8444-444444444444.m4a";

  @Mock private AudioStorage audioStorage;

  private StorageDelegatingStoredAudioReader reader;

  @BeforeEach
  void setUp() {
    reader = new StorageDelegatingStoredAudioReader(audioStorage);
  }

  @Test
  void readsAudioThroughConfiguredStorage() {
    InputStream stream = new ByteArrayInputStream(new byte[] {1, 2, 3});
    given(audioStorage.read(STORAGE_KEY))
        .willReturn(new StoredAudioContent(stream, "audio/mp4", 3L));

    OpenedAudio opened = reader.open(STORAGE_KEY);

    // 저장에 쓴 경계로 읽어야 s3 모드에서도 같은 위치를 본다(S15P11B209-723).
    assertThat(opened.inputStream()).isSameAs(stream);
  }

  @Test
  void buildsTransferFilenameFromKeyExtension() {
    given(audioStorage.read(STORAGE_KEY))
        .willReturn(
            new StoredAudioContent(new ByteArrayInputStream(new byte[] {1}), "audio/mp4", 1L));

    OpenedAudio opened = reader.open(STORAGE_KEY);

    // AI 서버가 확장자로 음성 형식을 판별하므로 확장자는 살리고 원본 이름·경로는 노출하지 않는다.
    assertThat(opened.transferFilename()).isEqualTo("voice.m4a");
  }

  @Test
  void fallsBackToBinWhenKeyHasNoExtension() {
    String keyWithoutExtension = "2026/07/29/no-extension";
    given(audioStorage.read(keyWithoutExtension))
        .willReturn(
            new StoredAudioContent(new ByteArrayInputStream(new byte[] {1}), "audio/mp4", 1L));

    assertThat(reader.open(keyWithoutExtension).transferFilename()).isEqualTo("voice.bin");
  }

  @Test
  void translatesStorageFailureToSttUnavailable() {
    given(audioStorage.read(STORAGE_KEY))
        .willThrow(new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND));

    // 대화 화면에는 "음성을 쓸 수 없다"만 필요하고 내부 저장 구조를 드러낼 이유가 없다.
    assertThatThrownBy(() -> reader.open(STORAGE_KEY))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE));
  }
}
