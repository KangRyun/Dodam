package com.ssafy.b209.storage.audio;

import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Locale;
import java.util.Objects;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * 288 음성 저장 Root에서 심볼릭 링크와 경로 이탈을 차단하고 파일을 읽는 구현체다.
 *
 * <p>업로드 검증·저장·삭제를 수행하지 않는다. 이 구현은 289가 이미 검증되어 보관된 파일을 내부 AI에 Stream으로 전달하는 읽기 책임만 가진다.
 *
 * <p>⚠️ {@code app.storage.mode=local}에서만 등록한다(S15P11B209-723). 이전에는 모드와 무관하게 등록돼 s3 모드에서도 이 구현이
 * 이겼고, 파일은 MinIO에 있는데 로컬 Root를 뒤지다 STT가 전부 실패했다. s3 모드에서는 {@link
 * StorageDelegatingStoredAudioReader}가 등록된다.
 */
@Component
@ConditionalOnProperty(
    prefix = "app.storage",
    name = "mode",
    havingValue = "local",
    matchIfMissing = true)
public class LocalStoredAudioReader implements StoredAudioReader {

  private final Path root;

  /**
   * 저장 Root를 정규화해 읽기 경계를 만든다.
   *
   * @param properties 288과 공유하는 음성 저장 Root 설정
   */
  public LocalStoredAudioReader(AudioStorageProperties properties) {
    this.root = Objects.requireNonNull(properties, "properties must not be null").root();
  }

  /** {@inheritDoc} */
  @Override
  public OpenedAudio open(String storageKey) {
    try {
      Path safeRoot = root.toRealPath(LinkOption.NOFOLLOW_LINKS);
      Path candidate = resolveSafeFile(safeRoot, storageKey);
      return new OpenedAudio(
          Files.newInputStream(candidate, StandardOpenOption.READ), transferFilename(storageKey));
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE, exception);
    }
  }

  private Path resolveSafeFile(Path safeRoot, String storageKey) throws IOException {
    if (storageKey == null
        || storageKey.isBlank()
        || storageKey.indexOf('\\') >= 0
        || storageKey.startsWith("/")
        || storageKey.contains("..")) {
      throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE);
    }
    Path relative = Path.of(storageKey).normalize();
    if (relative.isAbsolute() || relative.getNameCount() != 4) {
      throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE);
    }
    Path current = safeRoot;
    for (int index = 0; index < relative.getNameCount(); index++) {
      current = current.resolve(relative.getName(index).toString()).normalize();
      if (!current.startsWith(safeRoot)
          || !Files.exists(current, LinkOption.NOFOLLOW_LINKS)
          || Files.isSymbolicLink(current)) {
        throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE);
      }
      if (index < relative.getNameCount() - 1) {
        if (!Files.isDirectory(current, LinkOption.NOFOLLOW_LINKS)) {
          throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE);
        }
        current = current.toRealPath(LinkOption.NOFOLLOW_LINKS);
      }
    }
    if (!Files.isRegularFile(current, LinkOption.NOFOLLOW_LINKS)) {
      throw new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE);
    }
    return current;
  }

  private String transferFilename(String storageKey) {
    int dot = storageKey.lastIndexOf('.');
    String extension = dot < 0 ? "bin" : storageKey.substring(dot + 1).toLowerCase(Locale.ROOT);
    return "voice." + extension.replaceAll("[^a-z0-9]", "");
  }
}
