package com.ssafy.b209.storage.image;

import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
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
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

/**
 * 이미지 Stream을 설정된 로컬 파일 시스템 Root에 저장하는 {@link ImageStorage} 구현체다.
 *
 * <p>입력을 제한된 Buffer로 한 번만 읽으며 실제 Signature·크기·MIME Type·확장자를 교차 검증한다. 임시 파일을 완성한 뒤 최종 파일로 이동하고,
 * 호출자가 제공한 파일명이나 서버 절대 경로를 저장 Key에 사용하지 않는다.
 */
public final class LocalImageStorage implements ImageStorage {

  private static final int BUFFER_SIZE = 8192;
  private static final int HEADER_SIZE = 12;
  private static final int MAX_FILE_NAME_ATTEMPTS = 10;

  private final Path configuredRoot;
  private final long maxSize;
  private final Clock clock;
  private final Supplier<UUID> uuidSupplier;

  /**
   * 운영 설정과 UTC 기준 시계를 사용하는 로컬 이미지 저장소를 생성한다.
   *
   * <p>Root 디렉터리는 첫 저장 시점에 생성하고 검증한다.
   *
   * @param properties Storage Root와 최대 이미지 크기 설정
   * @param clock 날짜별 상대 Key를 생성할 때 사용하는 시계
   */
  public LocalImageStorage(ImageStorageProperties properties, Clock clock) {
    this(properties, clock, UUID::randomUUID);
  }

  /**
   * 상대 Storage Key가 가리키는 로컬 이미지를 안전하게 조회한다.
   *
   * @param storageKey 저장 시 반환된 {@code /} 구분 상대 Key
   * @return 이미지 Stream과 Content-Type, 크기
   * @throws BusinessException Key가 Storage Root를 벗어나거나 파일이 없거나 조회에 실패한 경우
   */
  @Override
  public StoredImageContent read(String storageKey) {
    try {
      String[] segments = validateStorageKey(storageKey);
      Path target = resolveExistingFile(prepareRoot(), segments);
      if (target == null) {
        throw new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND);
      }
      ImageFormat format = ImageFormat.fromStoredFileName(target.getFileName().toString());
      long size = Files.size(target);
      if (size <= 0) {
        throw new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND);
      }
      return new StoredImageContent(
          Files.newInputStream(target, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS),
          format.contentType,
          size);
    } catch (BusinessException exception) {
      throw exception;
    } catch (NoSuchFileException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND);
    } catch (InvalidPathException exception) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
    }
  }

  LocalImageStorage(ImageStorageProperties properties, Clock clock, Supplier<UUID> uuidSupplier) {
    ImageStorageProperties requiredProperties =
        Objects.requireNonNull(properties, "properties must not be null");
    this.configuredRoot = requiredProperties.root();
    this.maxSize = requiredProperties.maxSize();
    this.clock = Objects.requireNonNull(clock, "clock must not be null");
    this.uuidSupplier = Objects.requireNonNull(uuidSupplier, "uuidSupplier must not be null");
  }

  /**
   * 이미지 Stream을 검증해 날짜·UUID 기반 상대 Key로 저장한다.
   *
   * <p>이 메서드는 전달받은 Stream을 한 번만 소비하고 모든 종료 경로에서 닫는다. 저장 실패 시 생성 중인 임시 파일을 정리하며 기존 파일을 덮어쓰지 않는다.
   *
   * @param command 이미지 Stream과 호출자가 알고 있는 Metadata
   * @return 검증된 MIME Type, 실제 크기와 상대 Storage Key
   * @throws BusinessException 입력 이미지 또는 저장 경로가 유효하지 않거나 파일 시스템 저장에 실패한 경우
   */
  @Override
  public StoredImage store(StoreImageCommand command) {
    if (command == null) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
    if (command.inputStream() == null) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }

    Path temporaryFile = null;
    try {
      Path root;
      LocalDate date;
      Path targetDirectory;
      ImageFormat declaredFormat;
      CopyResult copied;
      try (InputStream inputStream = command.inputStream()) {
        validateDeclaredSize(command.size());
        declaredFormat = ImageFormat.fromContentType(command.contentType());
        validateOriginalExtension(command.originalFilename(), declaredFormat);

        root = prepareRoot();
        date = LocalDate.now(clock);
        targetDirectory = prepareDateDirectory(root, date);
        temporaryFile = Files.createTempFile(targetDirectory, ".image-", ".tmp");

        copied = copyToTemporaryFile(inputStream, temporaryFile);
        validateCopiedImage(command.size(), copied, declaredFormat);
      }
      ImageMetadataSanitizer.sanitize(temporaryFile, declaredFormat.imageIoFormatName);
      StoredFileMetadata metadata = readStoredFileMetadata(temporaryFile);
      return moveToFinalFile(
          temporaryFile,
          root,
          targetDirectory,
          date,
          declaredFormat,
          metadata.size(),
          metadata.checksumSha256(),
          metadata.dimensions());
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
    } finally {
      deleteTemporaryFile(temporaryFile);
    }
  }

  /**
   * 로컬 Storage Root 내부의 이미지 한 건을 보상 삭제한다.
   *
   * @param storageKey 저장 시 반환된 {@code /} 구분 상대 Key
   * @throws BusinessException Key가 Root를 벗어나거나 파일 시스템 삭제에 실패한 경우
   */
  @Override
  public void delete(String storageKey) {
    try {
      String[] segments = validateStorageKey(storageKey);
      Path root = prepareRoot();
      Path target = resolveExistingFile(root, segments);
      if (target == null) {
        return;
      }
      Files.deleteIfExists(target);
    } catch (BusinessException exception) {
      throw exception;
    } catch (InvalidPathException exception) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
    }
  }

  private Path resolveExistingFile(Path root, String[] segments) throws IOException {
    Path current = root;
    for (int index = 0; index < segments.length - 1; index++) {
      Path candidate = current.resolve(segments[index]).normalize();
      validateInsideRoot(root, candidate);
      if (!Files.exists(candidate, LinkOption.NOFOLLOW_LINKS)) {
        return null;
      }
      if (Files.isSymbolicLink(candidate)
          || !Files.isDirectory(candidate, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
      }
      current = candidate.toRealPath();
      validateInsideRoot(root, current);
    }

    Path target = current.resolve(segments[segments.length - 1]).normalize();
    validateInsideRoot(root, target);
    if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
      return null;
    }
    if (Files.isSymbolicLink(target) || !Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }
    return target;
  }

  private void validateDeclaredSize(long size) {
    if (size <= 0) {
      throw new BusinessException(ImageStorageErrorCode.EMPTY_IMAGE_FILE);
    }
    if (size > maxSize) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_FILE_TOO_LARGE);
    }
  }

  private Path prepareRoot() throws IOException {
    if (Files.exists(configuredRoot, LinkOption.NOFOLLOW_LINKS)) {
      if (Files.isSymbolicLink(configuredRoot)) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
      }
      if (!Files.isDirectory(configuredRoot, LinkOption.NOFOLLOW_LINKS)) {
        throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
      }
    } else {
      Files.createDirectories(configuredRoot);
    }

    Path root = configuredRoot.toRealPath();
    if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
    }
    return root;
  }

  private Path prepareDateDirectory(Path root, LocalDate date) throws IOException {
    Path current = root;
    String[] segments = {
      Integer.toString(date.getYear()),
      String.format(Locale.ROOT, "%02d", date.getMonthValue()),
      String.format(Locale.ROOT, "%02d", date.getDayOfMonth())
    };

    for (String segment : segments) {
      Path candidate = current.resolve(segment).normalize();
      validateInsideRoot(root, candidate);
      ensureSafeDirectory(candidate);
      current = candidate.toRealPath();
      validateInsideRoot(root, current);
    }
    return current;
  }

  private void ensureSafeDirectory(Path directory) throws IOException {
    try {
      Files.createDirectory(directory);
    } catch (FileAlreadyExistsException ignored) {
      // 아래의 NOFOLLOW_LINKS 검사에서 기존 경로가 안전한 디렉터리인지 판별한다.
    }
    if (Files.isSymbolicLink(directory)
        || !Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }
  }

  private CopyResult copyToTemporaryFile(InputStream inputStream, Path temporaryFile)
      throws IOException {
    byte[] buffer = new byte[BUFFER_SIZE];
    byte[] header = new byte[HEADER_SIZE];
    int headerLength = 0;
    long total = 0;

    try (OutputStream outputStream =
        Files.newOutputStream(temporaryFile, StandardOpenOption.WRITE)) {
      int read;
      while ((read = inputStream.read(buffer)) != -1) {
        if (read == 0) {
          continue;
        }
        if (total > maxSize - read) {
          throw new BusinessException(ImageStorageErrorCode.IMAGE_FILE_TOO_LARGE);
        }
        int headerBytes = Math.min(read, HEADER_SIZE - headerLength);
        if (headerBytes > 0) {
          System.arraycopy(buffer, 0, header, headerLength, headerBytes);
          headerLength += headerBytes;
        }
        outputStream.write(buffer, 0, read);
        total += read;
      }
    }
    return new CopyResult(header, headerLength, total);
  }

  private void validateCopiedImage(
      long declaredSize, CopyResult copied, ImageFormat declaredFormat) {
    if (copied.size() == 0) {
      throw new BusinessException(ImageStorageErrorCode.EMPTY_IMAGE_FILE);
    }
    if (copied.size() != declaredSize) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
    ImageFormat detected = ImageFormat.fromSignature(copied.header(), copied.headerLength());
    if (detected == null || detected != declaredFormat) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
  }

  private StoredImage moveToFinalFile(
      Path temporaryFile,
      Path root,
      Path targetDirectory,
      LocalDate date,
      ImageFormat format,
      long size,
      String checksumSha256,
      ImageDimensions dimensions)
      throws IOException {
    for (int attempt = 0; attempt < MAX_FILE_NAME_ATTEMPTS; attempt++) {
      UUID uuid = uuidSupplier.get();
      if (uuid == null) {
        continue;
      }
      String storedFileName = uuid + "." + format.extension;
      Path destination = targetDirectory.resolve(storedFileName).normalize();
      validateInsideRoot(root, destination);
      if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
        continue;
      }

      try {
        moveWithoutOverwrite(temporaryFile, destination);
        String storageKey =
            String.format(
                Locale.ROOT,
                "%04d/%02d/%02d/%s",
                date.getYear(),
                date.getMonthValue(),
                date.getDayOfMonth(),
                storedFileName);
        return new StoredImage(
            storageKey,
            storedFileName,
            format.contentType,
            size,
            checksumSha256,
            dimensions.widthPx(),
            dimensions.heightPx());
      } catch (FileAlreadyExistsException ignored) {
        // 동시에 같은 UUID가 선점된 경우 새 UUID로 재시도한다.
      }
    }
    throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_CONFLICT);
  }

  private void moveWithoutOverwrite(Path source, Path destination) throws IOException {
    try {
      Files.move(source, destination, StandardCopyOption.ATOMIC_MOVE);
    } catch (AtomicMoveNotSupportedException ignored) {
      Files.move(source, destination);
    }
  }

  private ImageDimensions readImageDimensions(Path imageFile) {
    try (ImageInputStream imageInput = ImageIO.createImageInputStream(imageFile.toFile())) {
      if (imageInput == null) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
      }
      var readers = ImageIO.getImageReaders(imageInput);
      if (!readers.hasNext()) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
      }
      ImageReader reader = readers.next();
      try {
        reader.setInput(imageInput, true, true);
        int width = reader.getWidth(0);
        int height = reader.getHeight(0);
        if (width <= 0 || height <= 0) {
          throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
        }
        return new ImageDimensions(width, height);
      } finally {
        reader.dispose();
      }
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | RuntimeException exception) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
  }

  private StoredFileMetadata readStoredFileMetadata(Path imageFile) throws IOException {
    long size = Files.size(imageFile);
    if (size <= 0) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
    if (size > maxSize) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_FILE_TOO_LARGE);
    }
    MessageDigest checksum = sha256Digest();
    try (InputStream input = Files.newInputStream(imageFile, StandardOpenOption.READ)) {
      byte[] buffer = new byte[BUFFER_SIZE];
      int read;
      while ((read = input.read(buffer)) != -1) {
        if (read > 0) {
          checksum.update(buffer, 0, read);
        }
      }
    }
    return new StoredFileMetadata(
        size, HexFormat.of().formatHex(checksum.digest()), readImageDimensions(imageFile));
  }

  private void validateInsideRoot(Path root, Path candidate) {
    if (!candidate.isAbsolute() || !candidate.normalize().startsWith(root)) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }
  }

  private String[] validateStorageKey(String storageKey) {
    if (storageKey == null
        || storageKey.isBlank()
        || storageKey.indexOf('\\') >= 0
        || Path.of(storageKey).isAbsolute()) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }
    String[] segments = storageKey.split("/", -1);
    if (segments.length == 0) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }
    for (String segment : segments) {
      if (segment.isBlank() || ".".equals(segment) || "..".equals(segment)) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
      }
    }
    return segments;
  }

  private MessageDigest sha256Digest() {
    try {
      return MessageDigest.getInstance("SHA-256");
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 algorithm is unavailable", exception);
    }
  }

  private void validateOriginalExtension(String originalFilename, ImageFormat format) {
    if (originalFilename == null || originalFilename.isBlank()) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
    for (int index = 0; index < originalFilename.length(); index++) {
      char character = originalFilename.charAt(index);
      if (character == 0 || Character.isISOControl(character)) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
      }
    }

    int dotIndex = originalFilename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == originalFilename.length() - 1) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
    String extension = originalFilename.substring(dotIndex + 1).toLowerCase(Locale.ROOT);
    if (!format.acceptedExtensions.contains(extension)) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
  }

  private void deleteTemporaryFile(Path temporaryFile) {
    if (temporaryFile == null) {
      return;
    }
    try {
      Files.deleteIfExists(temporaryFile);
    } catch (IOException | SecurityException ignored) {
      // 임시 파일 정리 오류가 원래의 안전한 저장 오류를 덮어쓰지 않도록 한다.
    }
  }

  private record CopyResult(byte[] header, int headerLength, long size) {}

  private record ImageDimensions(int widthPx, int heightPx) {}

  private record StoredFileMetadata(long size, String checksumSha256, ImageDimensions dimensions) {}

  private enum ImageFormat {
    PNG("image/png", "png", "png", Set.of("png")),
    JPEG("image/jpeg", "jpg", "jpeg", Set.of("jpg", "jpeg"));

    private final String contentType;
    private final String extension;
    private final String imageIoFormatName;
    private final Set<String> acceptedExtensions;

    ImageFormat(
        String contentType,
        String extension,
        String imageIoFormatName,
        Set<String> acceptedExtensions) {
      this.contentType = contentType;
      this.extension = extension;
      this.imageIoFormatName = imageIoFormatName;
      this.acceptedExtensions = acceptedExtensions;
    }

    private static ImageFormat fromContentType(String contentType) {
      if (contentType == null) {
        throw new BusinessException(ImageStorageErrorCode.UNSUPPORTED_IMAGE_FORMAT);
      }
      String normalized = contentType.trim().toLowerCase(Locale.ROOT);
      if ("image/jpg".equals(normalized)) {
        normalized = "image/jpeg";
      }
      for (ImageFormat format : values()) {
        if (format.contentType.equals(normalized)) {
          return format;
        }
      }
      throw new BusinessException(ImageStorageErrorCode.UNSUPPORTED_IMAGE_FORMAT);
    }

    private static ImageFormat fromStoredFileName(String storedFileName) {
      String normalized = storedFileName.toLowerCase(Locale.ROOT);
      for (ImageFormat format : values()) {
        if (normalized.endsWith("." + format.extension)) {
          return format;
        }
      }
      throw new BusinessException(ImageStorageErrorCode.INVALID_STORAGE_PATH);
    }

    private static ImageFormat fromSignature(byte[] header, int length) {
      if (length >= 8
          && (header[0] & 0xFF) == 0x89
          && header[1] == 0x50
          && header[2] == 0x4E
          && header[3] == 0x47
          && header[4] == 0x0D
          && header[5] == 0x0A
          && header[6] == 0x1A
          && header[7] == 0x0A) {
        return PNG;
      }
      if (length >= 3
          && (header[0] & 0xFF) == 0xFF
          && (header[1] & 0xFF) == 0xD8
          && (header[2] & 0xFF) == 0xFF) {
        return JPEG;
      }
      return null;
    }
  }
}
