package com.ssafy.b209.storage.audio;

import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Objects;
import java.util.UUID;

/**
 * 음성 Stream을 별도 Root에 임시 저장·검증한 뒤 최종 승격하는 로컬 구현체다.
 *
 * <p>Content-Type·확장자·실제 signature를 모두 확인하고, 실제 Byte를 스트리밍해 20MiB와 SHA-256을 판정한다. 상대 key만 만들며 원본
 * 파일명·절대 경로는 영속화 또는 공개 응답에 사용하지 않는다.
 */
public final class LocalAudioStorage implements AudioStorage {
  private static final int BUFFER_SIZE = 8192;
  private static final int HEADER_SIZE = 64;
  private static final long MAX_DURATION_MILLIS = 60_000L;
  private static final int MAX_NAME_ATTEMPTS = 10;

  private final Path configuredRoot;
  private final long maxSize;
  private final Clock clock;

  /**
   * 음성 저장소를 생성한다.
   *
   * @param properties 음성 Root와 실제 Byte 제한
   * @param clock 상대 key 날짜 기준 시계
   */
  public LocalAudioStorage(AudioStorageProperties properties, Clock clock) {
    this.configuredRoot = Objects.requireNonNull(properties, "properties must not be null").root();
    this.maxSize = properties.maxSize();
    this.clock = Objects.requireNonNull(clock, "clock must not be null");
  }

  /** {@inheritDoc} */
  @Override
  public StagedAudio stage(StoreAudioCommand command) {
    if (command == null || command.inputStream() == null || command.size() <= 0) {
      throw new BusinessException(AudioStorageErrorCode.EMPTY_AUDIO_FILE);
    }
    if (command.size() > maxSize) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_FILE_TOO_LARGE);
    }
    AudioFormat declared =
        AudioFormat.fromDeclared(command.contentType(), command.originalFilename());
    Path temporary = null;
    try (InputStream input = command.inputStream()) {
      Path root = prepareRoot();
      Path staging = prepareDirectory(root, ".staging");
      temporary = Files.createTempFile(staging, ".audio-", ".tmp");
      CopyResult copied = copy(input, temporary);
      if (copied.size() == 0) {
        throw new BusinessException(AudioStorageErrorCode.EMPTY_AUDIO_FILE);
      }
      if (copied.size() != command.size()) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_AUDIO_FILE);
      }
      AudioFormat detected = AudioFormat.detect(copied.header(), copied.headerLength());
      if (detected == null || detected != declared) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_AUDIO_FILE);
      }
      long durationMillis = readDurationMillis(temporary, detected);
      if (durationMillis <= 0) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_AUDIO_FILE);
      }
      if (durationMillis > MAX_DURATION_MILLIS) {
        throw new BusinessException(AudioStorageErrorCode.AUDIO_DURATION_EXCEEDED);
      }
      return new StagedAudio(
          temporary, detected, copied.size(), copied.checksumSha256(), durationMillis);
    } catch (BusinessException exception) {
      deleteQuietly(temporary);
      throw exception;
    } catch (IOException | SecurityException exception) {
      deleteQuietly(temporary);
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
    }
  }

  /** {@inheritDoc} */
  @Override
  public StoredAudio promote(StagedAudio stagedAudio) {
    if (stagedAudio == null || stagedAudio.temporaryFile() == null) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_AUDIO_FILE);
    }
    try {
      Path root = prepareRoot();
      Path staging = prepareDirectory(root, ".staging");
      Path temporary = stagedAudio.temporaryFile().toRealPath(LinkOption.NOFOLLOW_LINKS);
      validateInside(staging, temporary);
      if (!Files.isRegularFile(temporary, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
      LocalDate date = LocalDate.now(clock);
      Path targetDirectory = prepareDateDirectory(root, date);
      for (int attempt = 0; attempt < MAX_NAME_ATTEMPTS; attempt++) {
        String filename = UUID.randomUUID() + "." + stagedAudio.format().extension();
        Path target = targetDirectory.resolve(filename).normalize();
        validateInside(root, target);
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
          continue;
        }
        try {
          moveNoReplace(temporary, target);
          return new StoredAudio(
              String.format(
                  Locale.ROOT,
                  "%04d/%02d/%02d/%s",
                  date.getYear(),
                  date.getMonthValue(),
                  date.getDayOfMonth(),
                  filename),
              stagedAudio.format().contentType(),
              stagedAudio.size(),
              stagedAudio.checksumSha256(),
              stagedAudio.durationMillis());
        } catch (FileAlreadyExistsException ignored) {
          // UUID 충돌 또는 동시 생성은 다음 UUID로 재시도한다.
        }
      }
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_CONFLICT);
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
    }
  }

  /** {@inheritDoc} */
  @Override
  public StoredAudioContent read(String storageKey) {
    try {
      String[] segments = validateKey(storageKey);
      Path root = prepareRoot();
      Path current = root;
      for (int index = 0; index < segments.length - 1; index++) {
        Path candidate = current.resolve(segments[index]).normalize();
        validateInside(root, candidate);
        if (!Files.exists(candidate, LinkOption.NOFOLLOW_LINKS)) {
          throw new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND);
        }
        if (Files.isSymbolicLink(candidate)
            || !Files.isDirectory(candidate, LinkOption.NOFOLLOW_LINKS)) {
          throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
        }
        current = candidate.toRealPath();
        validateInside(root, current);
      }

      Path target = current.resolve(segments[segments.length - 1]).normalize();
      validateInside(root, target);
      if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND);
      }
      if (Files.isSymbolicLink(target) || !Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
      String filename = target.getFileName().toString();
      int dot = filename.lastIndexOf('.');
      String contentType =
          dot < 0 ? null : AudioFormat.contentTypeForExtension(filename.substring(dot + 1));
      if (contentType == null) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
      long size = Files.size(target);
      if (size <= 0) {
        throw new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND);
      }
      return new StoredAudioContent(
          Files.newInputStream(target, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS),
          contentType,
          size);
    } catch (BusinessException exception) {
      throw exception;
    } catch (NoSuchFileException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_NOT_FOUND);
    } catch (InvalidPathException exception) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
    }
  }

  /** {@inheritDoc} */
  @Override
  public void discard(StagedAudio stagedAudio) {
    if (stagedAudio != null) {
      deleteQuietly(stagedAudio.temporaryFile());
    }
  }

  /** {@inheritDoc} */
  @Override
  public void delete(String storageKey) {
    try {
      String[] segments = validateKey(storageKey);
      Path root = prepareRoot();
      Path current = root;
      for (int index = 0; index < segments.length - 1; index++) {
        Path candidate = current.resolve(segments[index]).normalize();
        validateInside(root, candidate);
        if (!Files.exists(candidate, LinkOption.NOFOLLOW_LINKS)) return;
        if (Files.isSymbolicLink(candidate)
            || !Files.isDirectory(candidate, LinkOption.NOFOLLOW_LINKS)) {
          throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
        }
        current = candidate.toRealPath();
        validateInside(root, current);
      }
      Path target = current.resolve(segments[segments.length - 1]).normalize();
      validateInside(root, target);
      if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) return;
      if (Files.isSymbolicLink(target) || !Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
      Files.deleteIfExists(target);
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(AudioStorageErrorCode.AUDIO_STORAGE_FAILED);
    }
  }

  private CopyResult copy(InputStream input, Path temporary) throws IOException {
    byte[] buffer = new byte[BUFFER_SIZE];
    byte[] header = new byte[HEADER_SIZE];
    int headerLength = 0;
    long size = 0;
    MessageDigest digest = sha256();
    try (OutputStream output = Files.newOutputStream(temporary, StandardOpenOption.WRITE)) {
      int read;
      while ((read = input.read(buffer)) != -1) {
        if (read == 0) continue;
        if (size > maxSize - read) {
          throw new BusinessException(AudioStorageErrorCode.AUDIO_FILE_TOO_LARGE);
        }
        int headerBytes = Math.min(read, HEADER_SIZE - headerLength);
        if (headerBytes > 0) {
          System.arraycopy(buffer, 0, header, headerLength, headerBytes);
          headerLength += headerBytes;
        }
        output.write(buffer, 0, read);
        digest.update(buffer, 0, read);
        size += read;
      }
    }
    return new CopyResult(header, headerLength, size, HexFormat.of().formatHex(digest.digest()));
  }

  private long readDurationMillis(Path file, AudioFormat format) throws IOException {
    byte[] data = Files.readAllBytes(file);
    return switch (format) {
      case WAV -> wavDuration(data);
      case MP3 -> mp3Duration(data);
      case M4A -> mp4Duration(data);
      case WEBM -> webmDuration(data);
    };
  }

  private long wavDuration(byte[] data) {
    if (data.length < 44) return -1;
    int cursor = 12;
    long byteRate = -1;
    long dataSize = -1;
    while (cursor + 8 <= data.length) {
      String id = new String(data, cursor, 4, java.nio.charset.StandardCharsets.US_ASCII);
      long size = uint32Le(data, cursor + 4);
      cursor += 8;
      if (size < 0 || size > data.length - cursor) return -1;
      if ("fmt ".equals(id) && size >= 16) byteRate = uint32Le(data, cursor + 8);
      if ("data".equals(id)) {
        dataSize = size;
        break;
      }
      cursor += (int) size + ((size & 1) == 1 ? 1 : 0);
    }
    return byteRate <= 0 || dataSize <= 0 ? -1 : Math.max(1, dataSize * 1000 / byteRate);
  }

  private long mp3Duration(byte[] data) {
    int offset = id3Size(data);
    long totalMillis = 0;
    int frames = 0;
    while (offset + 4 <= data.length) {
      int header = ByteBuffer.wrap(data, offset, 4).order(ByteOrder.BIG_ENDIAN).getInt();
      if ((header & 0xFFE00000) != 0xFFE00000) return -1;
      int version = (header >>> 19) & 3;
      int layer = (header >>> 17) & 3;
      int bitrateIndex = (header >>> 12) & 15;
      int sampleIndex = (header >>> 10) & 3;
      int padding = (header >>> 9) & 1;
      if (version == 1 || layer != 1 || bitrateIndex == 0 || bitrateIndex == 15 || sampleIndex == 3)
        return -1;
      int sampleRate = mp3SampleRate(version, sampleIndex);
      int bitrate = mp3BitrateKbps(version, bitrateIndex);
      if (sampleRate <= 0 || bitrate <= 0) return -1;
      int samplesPerFrame = version == 3 ? 1152 : 576;
      int frameLength =
          (version == 3 ? 144000 * bitrate / sampleRate : 72000 * bitrate / sampleRate) + padding;
      if (frameLength <= 4 || offset + frameLength > data.length) return -1;
      totalMillis += Math.round(samplesPerFrame * 1000.0 / sampleRate);
      frames++;
      offset += frameLength;
    }
    return frames == 0 ? -1 : totalMillis;
  }

  private long mp4Duration(byte[] data) {
    int cursor = 0;
    while (cursor + 8 <= data.length) {
      Mp4Box box = readBox(data, cursor, data.length);
      if (box == null) return -1;
      if ("moov".equals(box.type())) {
        return findMvhdDuration(data, cursor + box.headerSize(), cursor + (int) box.totalSize());
      }
      cursor += (int) box.totalSize();
    }
    return -1;
  }

  private long findMvhdDuration(byte[] data, int start, int end) {
    for (int cursor = start; cursor + 8 <= end; ) {
      Mp4Box box = readBox(data, cursor, end);
      if (box == null) return -1;
      if ("mvhd".equals(box.type())) {
        int payload = cursor + box.headerSize();
        int boxEnd = cursor + (int) box.totalSize();
        if (payload >= boxEnd) return -1;
        int version = data[payload] & 0xFF;
        if (version == 0 && payload + 20 <= boxEnd) {
          long timeScale = uint32Be(data, payload + 12);
          long duration = uint32Be(data, payload + 16);
          return timeScale <= 0 || duration <= 0 ? -1 : duration * 1000 / timeScale;
        }
        if (version == 1 && payload + 32 <= boxEnd) {
          long timeScale = uint32Be(data, payload + 20);
          long duration = uint64Be(data, payload + 24);
          return timeScale <= 0 || duration <= 0 ? -1 : duration * 1000 / timeScale;
        }
        return -1;
      }
      cursor += (int) box.totalSize();
    }
    return -1;
  }

  private Mp4Box readBox(byte[] data, int cursor, int end) {
    if (cursor + 8 > end) return null;
    long size = uint32Be(data, cursor);
    String type = new String(data, cursor + 4, 4, java.nio.charset.StandardCharsets.US_ASCII);
    long totalSize;
    int headerSize;
    if (size == 1) {
      if (cursor + 16 > end) return null;
      long largesize = uint64Be(data, cursor + 8);
      totalSize = largesize;
      headerSize = 16;
    } else if (size == 0) {
      totalSize = (long) end - cursor;
      headerSize = 8;
    } else {
      totalSize = size;
      headerSize = 8;
    }
    if (totalSize < headerSize || totalSize > end - cursor) return null;
    return new Mp4Box(type, totalSize, headerSize);
  }

  private long webmDuration(byte[] data) {
    long scale = 1_000_000L;
    for (int index = 0; index + 3 < data.length; index++) {
      if ((data[index] & 0xFF) == 0x2A
          && (data[index + 1] & 0xFF) == 0xD7
          && (data[index + 2] & 0xFF) == 0xB1) {
        Vint size = vint(data, index + 3);
        if (size != null
            && size.value() > 0
            && size.value() <= 8
            && index + 3 + size.length() + size.value() <= data.length) {
          scale = unsigned(data, index + 3 + size.length(), (int) size.value());
        }
      }
      if ((data[index] & 0xFF) == 0x44 && (data[index + 1] & 0xFF) == 0x89) {
        Vint size = vint(data, index + 2);
        if (size == null || (size.value() != 4 && size.value() != 8)) continue;
        int valueOffset = index + 2 + size.length();
        if (valueOffset + size.value() > data.length) return -1;
        ByteBuffer buffer =
            ByteBuffer.wrap(data, valueOffset, (int) size.value()).order(ByteOrder.BIG_ENDIAN);
        double duration = size.value() == 4 ? buffer.getFloat() : buffer.getDouble();
        if (!Double.isFinite(duration) || duration <= 0) return -1;
        return Math.round(duration * scale / 1_000_000.0);
      }
    }
    return -1;
  }

  private Path prepareRoot() throws IOException {
    if (Files.exists(configuredRoot, LinkOption.NOFOLLOW_LINKS)) {
      if (Files.isSymbolicLink(configuredRoot)
          || !Files.isDirectory(configuredRoot, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
    } else {
      Files.createDirectories(configuredRoot);
    }
    return configuredRoot.toRealPath();
  }

  private Path prepareDateDirectory(Path root, LocalDate date) throws IOException {
    Path current = root;
    for (String segment :
        new String[] {
          String.valueOf(date.getYear()),
          String.format(Locale.ROOT, "%02d", date.getMonthValue()),
          String.format(Locale.ROOT, "%02d", date.getDayOfMonth())
        }) {
      current = prepareDirectory(current, segment);
      validateInside(root, current);
    }
    return current;
  }

  private Path prepareDirectory(Path parent, String name) throws IOException {
    Path candidate = parent.resolve(name).normalize();
    validateInside(parent, candidate);
    try {
      Files.createDirectory(candidate);
    } catch (FileAlreadyExistsException ignored) {
      // 아래 검사에서 기존 경로가 안전한 실제 디렉터리인지 판별한다.
    }
    if (Files.isSymbolicLink(candidate)
        || !Files.isDirectory(candidate, LinkOption.NOFOLLOW_LINKS)) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
    }
    return candidate.toRealPath();
  }

  private void moveNoReplace(Path source, Path target) throws IOException {
    try {
      Files.move(source, target, StandardCopyOption.ATOMIC_MOVE);
    } catch (AtomicMoveNotSupportedException ignored) {
      Files.move(source, target);
    }
  }

  private void validateInside(Path root, Path candidate) {
    if (!candidate.isAbsolute() || !candidate.normalize().startsWith(root)) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
    }
  }

  private String[] validateKey(String storageKey) {
    if (storageKey == null
        || storageKey.isBlank()
        || storageKey.contains("\\")
        || Path.of(storageKey).isAbsolute()) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
    }
    String[] segments = storageKey.split("/", -1);
    for (String segment : segments) {
      if (segment.isBlank() || ".".equals(segment) || "..".equals(segment)) {
        throw new BusinessException(AudioStorageErrorCode.INVALID_STORAGE_PATH);
      }
    }
    return segments;
  }

  private int id3Size(byte[] data) {
    if (data.length < 10 || data[0] != 'I' || data[1] != 'D' || data[2] != '3') return 0;
    return 10
        + ((data[6] & 0x7F) << 21)
        + ((data[7] & 0x7F) << 14)
        + ((data[8] & 0x7F) << 7)
        + (data[9] & 0x7F);
  }

  private int mp3SampleRate(int version, int index) {
    int[][] values = {
      {11025, 12000, 8000}, {0, 0, 0}, {22050, 24000, 16000}, {44100, 48000, 32000}
    };
    return values[version][index];
  }

  private int mp3BitrateKbps(int version, int index) {
    int[] mpeg1 = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0};
    int[] mpeg2 = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0};
    return (version == 3 ? mpeg1 : mpeg2)[index];
  }

  private long uint32Le(byte[] source, int offset) {
    return ((long) source[offset] & 0xFF)
        | (((long) source[offset + 1] & 0xFF) << 8)
        | (((long) source[offset + 2] & 0xFF) << 16)
        | (((long) source[offset + 3] & 0xFF) << 24);
  }

  private long uint32Be(byte[] source, int offset) {
    return ByteBuffer.wrap(source, offset, 4).order(ByteOrder.BIG_ENDIAN).getInt() & 0xFFFF_FFFFL;
  }

  private long uint64Be(byte[] source, int offset) {
    long value = ByteBuffer.wrap(source, offset, 8).order(ByteOrder.BIG_ENDIAN).getLong();
    return value < 0 ? -1 : value;
  }

  private long unsigned(byte[] source, int offset, int length) {
    long value = 0;
    for (int index = 0; index < length; index++)
      value = (value << 8) | (source[offset + index] & 0xFFL);
    return value;
  }

  private Vint vint(byte[] source, int offset) {
    if (offset >= source.length) return null;
    int first = source[offset] & 0xFF;
    int length = Integer.numberOfLeadingZeros(first) - 23;
    if (length < 1 || length > 8 || offset + length > source.length) return null;
    long value = first & ((1 << (8 - length)) - 1);
    for (int index = 1; index < length; index++)
      value = (value << 8) | (source[offset + index] & 0xFFL);
    return new Vint(length, value);
  }

  private MessageDigest sha256() {
    try {
      return MessageDigest.getInstance("SHA-256");
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is unavailable", exception);
    }
  }

  private void deleteQuietly(Path path) {
    if (path == null) return;
    try {
      Files.deleteIfExists(path);
    } catch (IOException | SecurityException ignored) {
      // 원래의 검증·저장 오류를 임시 파일 정리 실패가 덮어쓰지 않는다.
    }
  }

  private record CopyResult(byte[] header, int headerLength, long size, String checksumSha256) {}

  private record Mp4Box(String type, long totalSize, int headerSize) {}

  private record Vint(int length, long value) {}
}
