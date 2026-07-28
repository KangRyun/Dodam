package com.ssafy.b209.storage.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.ssafy.b209.global.exception.BusinessException;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
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
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.stream.Stream;
import java.util.zip.CRC32;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LocalImageStorageTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-22T01:02:03Z"), ZoneOffset.UTC);
  private static final UUID FIRST_UUID = UUID.fromString("11111111-1111-4111-8111-111111111111");
  private static final UUID SECOND_UUID = UUID.fromString("22222222-2222-4222-8222-222222222222");
  private static final byte[] PNG = imageBytes("png");
  private static final byte[] JPEG = imageBytes("jpeg");
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
    assertThat(stored.widthPx()).isEqualTo(2);
    assertThat(stored.heightPx()).isEqualTo(3);
    assertThat(Path.of(stored.storageKey())).isRelative();
    assertThat(stored.storageKey()).doesNotContain("\\").doesNotContain(root.toString());
    byte[] sanitized = Files.readAllBytes(resolveStorageKey(root, stored.storageKey()));
    assertThat(stored.size()).isEqualTo(sanitized.length);
    assertThat(stored.checksumSha256()).isEqualTo(sha256(sanitized));
    assertThat(ImageIO.read(new ByteArrayInputStream(sanitized))).isNotNull();
  }

  private static byte[] imageBytes(String format) {
    BufferedImage image = new BufferedImage(2, 3, BufferedImage.TYPE_INT_RGB);
    try (ByteArrayOutputStream output = new ByteArrayOutputStream()) {
      if (!ImageIO.write(image, format, output)) {
        throw new IllegalStateException("Test image writer is unavailable: " + format);
      }
      return output.toByteArray();
    } catch (IOException exception) {
      throw new IllegalStateException("Failed to create a test image", exception);
    }
  }

  private static byte[] jpegWithExifOrientationAndGps() {
    BufferedImage image = new BufferedImage(20, 30, BufferedImage.TYPE_INT_RGB);
    for (int y = 0; y < image.getHeight(); y++) {
      for (int x = 0; x < image.getWidth(); x++) {
        image.setRGB(x, y, x < 10 && y < 10 ? 0x00FF0000 : 0x000000FF);
      }
    }
    byte[] jpeg = writeImage(image, "jpeg");
    byte[] exif =
        bytes(
            0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00,
            0x25, 0x88, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, 0x00, 0x4E, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
    int segmentLength = exif.length + 2;
    byte[] result = new byte[jpeg.length + exif.length + 4];
    result[0] = (byte) 0xFF;
    result[1] = (byte) 0xD8;
    result[2] = (byte) 0xFF;
    result[3] = (byte) 0xE1;
    result[4] = (byte) (segmentLength >>> 8);
    result[5] = (byte) segmentLength;
    System.arraycopy(exif, 0, result, 6, exif.length);
    System.arraycopy(jpeg, 2, result, 6 + exif.length, jpeg.length - 2);
    return result;
  }

  private static byte[] pngWithTextChunk(String keyword, String value) {
    int iendOffset = findPngChunkOffset(PNG, "IEND");
    byte[] data = (keyword + "\0" + value).getBytes(StandardCharsets.ISO_8859_1);
    byte[] type = "tEXt".getBytes(StandardCharsets.US_ASCII);
    CRC32 crc = new CRC32();
    crc.update(type);
    crc.update(data);
    byte[] chunk = new byte[12 + data.length];
    writeInt(chunk, 0, data.length);
    System.arraycopy(type, 0, chunk, 4, type.length);
    System.arraycopy(data, 0, chunk, 8, data.length);
    writeInt(chunk, 8 + data.length, (int) crc.getValue());
    byte[] result = new byte[PNG.length + chunk.length];
    System.arraycopy(PNG, 0, result, 0, iendOffset);
    System.arraycopy(chunk, 0, result, iendOffset, chunk.length);
    System.arraycopy(PNG, iendOffset, result, iendOffset + chunk.length, PNG.length - iendOffset);
    return result;
  }

  private static byte[] writeImage(BufferedImage image, String format) {
    try (ByteArrayOutputStream output = new ByteArrayOutputStream()) {
      if (!ImageIO.write(image, format, output)) {
        throw new IllegalStateException("Test image writer is unavailable: " + format);
      }
      return output.toByteArray();
    } catch (IOException exception) {
      throw new IllegalStateException("Failed to create a test image", exception);
    }
  }

  private static boolean hasJpegExifSegment(byte[] jpeg) {
    for (int index = 2; index + 10 <= jpeg.length; ) {
      if ((jpeg[index] & 0xFF) != 0xFF) {
        return false;
      }
      int marker = jpeg[index + 1] & 0xFF;
      if (marker == 0xDA || marker == 0xD9) {
        return false;
      }
      int length = ((jpeg[index + 2] & 0xFF) << 8) | (jpeg[index + 3] & 0xFF);
      if (marker == 0xE1
          && length >= 8
          && jpeg[index + 4] == 'E'
          && jpeg[index + 5] == 'x'
          && jpeg[index + 6] == 'i'
          && jpeg[index + 7] == 'f') {
        return true;
      }
      index += length + 2;
    }
    return false;
  }

  private static boolean hasPngMetadataChunk(byte[] png) {
    int offset = 8;
    while (offset + 12 <= png.length) {
      int length = readInt(png, offset);
      String type = new String(png, offset + 4, 4, StandardCharsets.US_ASCII);
      if (Set.of("tEXt", "zTXt", "iTXt", "eXIf").contains(type)) {
        return true;
      }
      if ("IEND".equals(type)) {
        return false;
      }
      offset += 12 + length;
    }
    return false;
  }

  private static int findPngChunkOffset(byte[] png, String expectedType) {
    int offset = 8;
    while (offset + 12 <= png.length) {
      int length = readInt(png, offset);
      String type = new String(png, offset + 4, 4, StandardCharsets.US_ASCII);
      if (expectedType.equals(type)) {
        return offset;
      }
      offset += 12 + length;
    }
    throw new IllegalArgumentException("PNG chunk not found: " + expectedType);
  }

  private static int readInt(byte[] bytes, int offset) {
    return ((bytes[offset] & 0xFF) << 24)
        | ((bytes[offset + 1] & 0xFF) << 16)
        | ((bytes[offset + 2] & 0xFF) << 8)
        | (bytes[offset + 3] & 0xFF);
  }

  private static void writeInt(byte[] bytes, int offset, int value) {
    bytes[offset] = (byte) (value >>> 24);
    bytes[offset + 1] = (byte) (value >>> 16);
    bytes[offset + 2] = (byte) (value >>> 8);
    bytes[offset + 3] = (byte) value;
  }

  private static boolean isRedDominant(int rgb) {
    int red = (rgb >>> 16) & 0xFF;
    int blue = rgb & 0xFF;
    return red > blue + 40;
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
    Path root = tempDir.resolve("images");
    LocalImageStorage storage = storage(root, 1024, () -> FIRST_UUID);

    StoredImage stored = storage.store(command(JPEG, "image/jpg", "drawing.JPEG"));

    assertThat(stored.contentType()).isEqualTo("image/jpeg");
    assertThat(stored.storedFileName()).endsWith(".jpg");
    byte[] sanitized = Files.readAllBytes(resolveStorageKey(root, stored.storageKey()));
    assertThat(stored.size()).isEqualTo(sanitized.length);
    assertThat(stored.checksumSha256()).isEqualTo(sha256(sanitized));
    assertThat(ImageIO.read(new ByteArrayInputStream(sanitized))).isNotNull();
  }

  @Test
  void removesExifMetadataAndAppliesOrientationBeforeStoringJpeg() throws IOException {
    Path root = tempDir.resolve("images");
    byte[] original = jpegWithExifOrientationAndGps();
    LocalImageStorage storage = storage(root, 1024 * 1024, () -> FIRST_UUID);

    StoredImage stored = storage.store(command(original, "image/jpeg", "drawing.jpg"));

    byte[] sanitized = Files.readAllBytes(resolveStorageKey(root, stored.storageKey()));
    BufferedImage decoded = ImageIO.read(new ByteArrayInputStream(sanitized));
    assertThat(hasJpegExifSegment(sanitized)).isFalse();
    assertThat(stored.widthPx()).isEqualTo(30);
    assertThat(stored.heightPx()).isEqualTo(20);
    assertThat(decoded.getWidth()).isEqualTo(30);
    assertThat(decoded.getHeight()).isEqualTo(20);
    assertThat(isRedDominant(decoded.getRGB(27, 2))).isTrue();
    assertThat(stored.size()).isEqualTo(sanitized.length);
    assertThat(stored.checksumSha256()).isEqualTo(sha256(sanitized));
  }

  @Test
  void removesTextMetadataBeforeStoringPng() throws IOException {
    Path root = tempDir.resolve("images");
    byte[] original = pngWithTextChunk("GPS", "37.5665,126.9780");
    LocalImageStorage storage = storage(root, 1024 * 1024, () -> FIRST_UUID);

    StoredImage stored = storage.store(command(original, "image/png", "drawing.png"));

    byte[] sanitized = Files.readAllBytes(resolveStorageKey(root, stored.storageKey()));
    assertThat(hasPngMetadataChunk(sanitized)).isFalse();
    assertThat(stored.widthPx()).isEqualTo(2);
    assertThat(stored.heightPx()).isEqualTo(3);
    assertThat(stored.size()).isEqualTo(sanitized.length);
    assertThat(stored.checksumSha256()).isEqualTo(sha256(sanitized));
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
