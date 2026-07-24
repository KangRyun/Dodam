package com.ssafy.b209.storage.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.ssafy.b209.global.exception.BusinessException;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HexFormat;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LocalImageStorageTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-22T01:02:03Z"), ZoneOffset.UTC);
  private static final UUID FIRST_UUID = UUID.fromString("11111111-1111-4111-8111-111111111111");
  private static final UUID SECOND_UUID = UUID.fromString("22222222-2222-4222-8222-222222222222");
  private static final byte[] PNG =
      bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03);
  private static final byte[] JPEG = bytes(0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0xFF, 0xD9);
  private static final byte[] WEBP =
      bytes(0x52, 0x49, 0x46, 0x46, 0x04, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50);

  @TempDir Path tempDir;

  @Test
  void storesPngUnderADateAndUuidRelativeKey() throws IOException {
    Path root = tempDir.resolve("missing-root");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    StoredImage stored = storage.store(command(PNG, "image/png", "child-picture.png"));

    assertThat(stored.storageKey())
        .isEqualTo("2026/07/22/11111111-1111-4111-8111-111111111111.png");
    assertThat(stored.storedFileName()).isEqualTo(FIRST_UUID + ".png");
    assertThat(stored.contentType()).isEqualTo("image/png");
    assertThat(stored.size()).isEqualTo(PNG.length);
    assertThat(stored.checksumSha256()).isEqualTo(sha256(PNG));
    assertThat(Path.of(stored.storageKey())).isRelative();
    assertThat(stored.storageKey()).doesNotContain("\\").doesNotContain(root.toString());
    assertThat(Files.readAllBytes(resolveStorageKey(root, stored.storageKey()))).isEqualTo(PNG);
  }

  @Test
  void deletesAStoredImageByItsRelativeKey() {
    Path root = tempDir.resolve("images");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);
    StoredImage stored = storage.store(command(PNG, "image/png", "drawing.png"));

    storage.delete(stored.storageKey());

    assertThat(resolveStorageKey(root, stored.storageKey())).doesNotExist();
  }

  @Test
  void readsAStoredImageWithoutExposingItsAbsolutePath() throws IOException {
    Path root = tempDir.resolve("images");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);
    StoredImage stored = storage.store(command(PNG, "image/png", "drawing.png"));

    try (StoredImageContent content = storage.read(stored.storageKey())) {
      assertThat(content.contentType()).isEqualTo("image/png");
      assertThat(content.size()).isEqualTo(PNG.length);
      assertThat(content.inputStream().readAllBytes()).isEqualTo(PNG);
      assertThat(content.toString()).doesNotContain(root.toString());
    }
  }

  @Test
  void rejectsMissingAndEscapingReadKeysWithoutOpeningAFile() {
    Path root = tempDir.resolve("images");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.read("2026/07/22/missing.png"), ImageStorageErrorCode.IMAGE_NOT_FOUND);
    assertBusinessError(
        () -> storage.read("../outside.png"), ImageStorageErrorCode.INVALID_STORAGE_PATH);
    assertBusinessError(
        () -> storage.read(root.resolve("drawing.png").toString()),
        ImageStorageErrorCode.INVALID_STORAGE_PATH);
  }

  @Test
  void rejectsASymbolicLinkInAReadKey() throws IOException {
    Path root = tempDir.resolve("images");
    Path outside = tempDir.resolve("outside.png");
    Files.createDirectories(root);
    Files.write(outside, PNG);
    try {
      Files.createSymbolicLink(root.resolve("linked.png"), outside);
    } catch (UnsupportedOperationException | IOException | SecurityException exception) {
      assumeTrue(false, "Symbolic links are unavailable: " + exception.getClass().getSimpleName());
    }
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.read("linked.png"), ImageStorageErrorCode.INVALID_STORAGE_PATH);
  }

  @Test
  void treatsDeletingAMissingImageAsCompleted() {
    LocalImageStorage storage = storage(tempDir.resolve("images"), 1024, () -> FIRST_UUID);

    storage.delete("2026/07/22/missing.png");
  }

  @Test
  void rejectsAbsoluteAndEscapingDeletionKeys() {
    Path root = tempDir.resolve("images");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.delete(root.resolve("drawing.png").toString()),
        ImageStorageErrorCode.INVALID_STORAGE_PATH);
    assertBusinessError(
        () -> storage.delete("../outside.png"), ImageStorageErrorCode.INVALID_STORAGE_PATH);
  }

  @Test
  void rejectsASymbolicLinkInADeletionKey() throws IOException {
    Path root = tempDir.resolve("images");
    Path outside = tempDir.resolve("outside");
    Files.createDirectories(root);
    Files.createDirectories(outside);
    try {
      Files.createSymbolicLink(root.resolve("linked"), outside);
    } catch (UnsupportedOperationException | IOException | SecurityException exception) {
      assumeTrue(false, "Symbolic links are unavailable: " + exception.getClass().getSimpleName());
    }
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.delete("linked/image.png"), ImageStorageErrorCode.INVALID_STORAGE_PATH);
  }

  @Test
  void storesJpegUsingNormalizedMimeAndExtension() throws IOException {
    LocalImageStorage storage = storage(tempDir.resolve("images"), 1024, () -> FIRST_UUID);

    StoredImage stored = storage.store(command(JPEG, "image/jpg", "drawing.JPEG"));

    assertThat(stored.contentType()).isEqualTo("image/jpeg");
    assertThat(stored.storedFileName()).endsWith(".jpg");
    assertThat(
            Files.readAllBytes(resolveStorageKey(tempDir.resolve("images"), stored.storageKey())))
        .isEqualTo(JPEG);
  }

  @Test
  void ignoresPathSegmentsInOriginalFilename() {
    Path root = tempDir.resolve("images");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    StoredImage stored = storage.store(command(PNG, "image/png", "../../outside.png"));

    assertThat(stored.storageKey()).doesNotContain("..").doesNotContain("outside");
    assertThat(tempDir.resolve("outside.png")).doesNotExist();
  }

  @Test
  void retriesAUuidCollisionWithoutOverwritingTheExistingFile() throws IOException {
    Path root = tempDir.resolve("images");
    Path dateDirectory = root.resolve(Path.of("2026", "07", "22"));
    Files.createDirectories(dateDirectory);
    Path existing = dateDirectory.resolve(FIRST_UUID + ".png");
    Files.writeString(existing, "existing", StandardCharsets.UTF_8);
    Deque<UUID> uuids = new ArrayDeque<>(java.util.List.of(FIRST_UUID, SECOND_UUID));
    LocalImageStorage storage = storage(root, 1024, uuids::removeFirst);

    StoredImage stored = storage.store(command(PNG, "image/png", "drawing.png"));

    assertThat(stored.storedFileName()).isEqualTo(SECOND_UUID + ".png");
    assertThat(Files.readString(existing, StandardCharsets.UTF_8)).isEqualTo("existing");
  }

  @Test
  void rejectsRepeatedUuidCollisionsWithoutOverwriting() throws IOException {
    Path root = tempDir.resolve("images");
    Path existing = root.resolve(Path.of("2026", "07", "22", FIRST_UUID + ".png"));
    Files.createDirectories(existing.getParent());
    Files.writeString(existing, "existing", StandardCharsets.UTF_8);
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(command(PNG, "image/png", "drawing.png")),
        ImageStorageErrorCode.IMAGE_STORAGE_CONFLICT);
    assertThat(Files.readString(existing, StandardCharsets.UTF_8)).isEqualTo("existing");
  }

  @Test
  void rejectsEmptyAndNegativeDeclaredSizesAndClosesStreams() {
    TrackingInputStream empty = new TrackingInputStream(new byte[0]);
    TrackingInputStream negative = new TrackingInputStream(PNG);
    LocalImageStorage storage = storage(tempDir.resolve("images"), 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(new StoreImageCommand(empty, 0, "image/png", "empty.png")),
        ImageStorageErrorCode.EMPTY_IMAGE_FILE);
    assertBusinessError(
        () -> storage.store(new StoreImageCommand(negative, -1, "image/png", "negative.png")),
        ImageStorageErrorCode.EMPTY_IMAGE_FILE);
    assertThat(empty.closed).isTrue();
    assertThat(negative.closed).isTrue();
  }

  @Test
  void rejectsDeclaredAndActualOversizedImages() {
    LocalImageStorage storage =
        storage(tempDir.resolve("images"), PNG.length - 1L, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(command(PNG, "image/png", "large.png")),
        ImageStorageErrorCode.IMAGE_FILE_TOO_LARGE);
    assertBusinessError(
        () ->
            storage.store(
                new StoreImageCommand(
                    new ByteArrayInputStream(PNG), PNG.length - 1L, "image/png", "large.png")),
        ImageStorageErrorCode.IMAGE_FILE_TOO_LARGE);
  }

  @Test
  void rejectsADeclaredSizeDifferentFromTheStreamSize() {
    LocalImageStorage storage = storage(tempDir.resolve("images"), 1024, () -> FIRST_UUID);

    assertBusinessError(
        () ->
            storage.store(
                new StoreImageCommand(
                    new ByteArrayInputStream(PNG), PNG.length + 1L, "image/png", "drawing.png")),
        ImageStorageErrorCode.INVALID_IMAGE_FILE);
  }

  @Test
  void rejectsSpoofedMimeExtensionAndUnsupportedFormats() {
    LocalImageStorage storage = storage(tempDir.resolve("images"), 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(command(PNG, "image/jpeg", "drawing.png")),
        ImageStorageErrorCode.INVALID_IMAGE_FILE);
    assertBusinessError(
        () -> storage.store(command(PNG, "image/png", "drawing.jpg")),
        ImageStorageErrorCode.INVALID_IMAGE_FILE);
    assertBusinessError(
        () -> storage.store(command(WEBP, "image/webp", "drawing.webp")),
        ImageStorageErrorCode.UNSUPPORTED_IMAGE_FORMAT);
    assertBusinessError(
        () -> storage.store(command(new byte[] {1, 2, 3, 4}, "image/png", "drawing.png")),
        ImageStorageErrorCode.INVALID_IMAGE_FILE);
  }

  @Test
  void rejectsANullCommandAndNullStream() {
    LocalImageStorage storage = storage(tempDir.resolve("images"), 1024, () -> FIRST_UUID);

    assertBusinessError(() -> storage.store(null), ImageStorageErrorCode.INVALID_IMAGE_FILE);
    assertBusinessError(
        () -> storage.store(new StoreImageCommand(null, 1, "image/png", "drawing.png")),
        ImageStorageErrorCode.INVALID_IMAGE_FILE);
  }

  @Test
  void removesTemporaryFileAndClosesStreamWhenCopyFails() throws IOException {
    Path root = tempDir.resolve("images");
    FailingInputStream input = new FailingInputStream(PNG);
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(new StoreImageCommand(input, PNG.length, "image/png", "drawing.png")),
        ImageStorageErrorCode.IMAGE_STORAGE_FAILED);

    assertThat(input.closed).isTrue();
    if (Files.exists(root)) {
      try (Stream<Path> paths = Files.walk(root)) {
        assertThat(paths.filter(path -> path.getFileName().toString().endsWith(".tmp"))).isEmpty();
      }
    }
  }

  @Test
  void doesNotPublishAFileWhenClosingTheInputStreamFails() throws IOException {
    Path root = tempDir.resolve("images");
    CloseFailingInputStream input = new CloseFailingInputStream(PNG);
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(new StoreImageCommand(input, PNG.length, "image/png", "drawing.png")),
        ImageStorageErrorCode.IMAGE_STORAGE_FAILED);

    assertThat(input.closed).isTrue();
    if (Files.exists(root)) {
      try (Stream<Path> paths = Files.walk(root)) {
        assertThat(paths.filter(Files::isRegularFile)).isEmpty();
      }
    }
  }

  @Test
  void rejectsARootThatIsARegularFile() throws IOException {
    Path root = tempDir.resolve("root-file");
    Files.writeString(root, "not a directory", StandardCharsets.UTF_8);
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(command(PNG, "image/png", "drawing.png")),
        ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
  }

  @Test
  void rejectsASymbolicLinkInTheGeneratedDatePath() throws IOException {
    Path root = tempDir.resolve("images");
    Path outside = tempDir.resolve("outside");
    Files.createDirectories(root);
    Files.createDirectories(outside);
    try {
      Files.createSymbolicLink(root.resolve("2026"), outside);
    } catch (UnsupportedOperationException | IOException | SecurityException exception) {
      assumeTrue(false, "Symbolic links are unavailable: " + exception.getClass().getSimpleName());
    }
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    assertBusinessError(
        () -> storage.store(command(PNG, "image/png", "drawing.png")),
        ImageStorageErrorCode.INVALID_STORAGE_PATH);
    try (Stream<Path> paths = Files.list(outside)) {
      assertThat(paths).isEmpty();
    }
  }

  private LocalImageStorage storage(Path root, long maxSize, Supplier<UUID> uuidSupplier) {
    return new LocalImageStorage(new ImageStorageProperties(root, maxSize), CLOCK, uuidSupplier);
  }

  private StoreImageCommand command(byte[] bytes, String contentType, String originalFilename) {
    return new StoreImageCommand(
        new ByteArrayInputStream(bytes), bytes.length, contentType, originalFilename);
  }

  private Path resolveStorageKey(Path root, String storageKey) {
    return root.resolve(storageKey.replace('/', java.io.File.separatorChar));
  }

  private void assertBusinessError(Runnable action, ImageStorageErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }

  private static byte[] bytes(int... values) {
    byte[] result = new byte[values.length];
    for (int index = 0; index < values.length; index++) {
      result[index] = (byte) values[index];
    }
    return result;
  }

  private static String sha256(byte[] bytes) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    } catch (NoSuchAlgorithmException exception) {
      throw new AssertionError(exception);
    }
  }

  private static class TrackingInputStream extends InputStream {
    private final ByteArrayInputStream delegate;
    protected boolean closed;

    TrackingInputStream(byte[] bytes) {
      delegate = new ByteArrayInputStream(bytes);
    }

    @Override
    public int read() {
      return delegate.read();
    }

    @Override
    public int read(byte[] bytes, int offset, int length) throws IOException {
      return delegate.read(bytes, offset, length);
    }

    @Override
    public void close() throws IOException {
      closed = true;
      delegate.close();
    }
  }

  private static final class FailingInputStream extends TrackingInputStream {
    private boolean firstRead = true;

    FailingInputStream(byte[] bytes) {
      super(bytes);
    }

    @Override
    public int read(byte[] bytes, int offset, int length) throws IOException {
      if (!firstRead) {
        throw new IOException("simulated copy failure");
      }
      firstRead = false;
      return super.read(bytes, offset, Math.min(length, 4));
    }
  }

  private static final class CloseFailingInputStream extends TrackingInputStream {

    CloseFailingInputStream(byte[] bytes) {
      super(bytes);
    }

    @Override
    public void close() throws IOException {
      super.close();
      throw new IOException("simulated close failure");
    }
  }
}
