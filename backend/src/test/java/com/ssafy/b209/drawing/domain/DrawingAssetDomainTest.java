package com.ssafy.b209.drawing.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.mockito.Mockito.mock;

import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DrawingAssetDomainTest {

  @Test
  void createsSnapshotAssetWithStoredImageMetadata() {
    DrawingSession session = mock(DrawingSession.class);
    LocalDateTime capturedAt = LocalDateTime.of(2026, 7, 22, 9, 30);
    LocalDateTime createdAt = LocalDateTime.of(2026, 7, 22, 9, 31);

    DrawingAsset asset =
        DrawingAsset.snapshot(
            session,
            DrawingAssetType.INTERMEDIATE,
            2,
            "2026/07/image.png",
            "image/png",
            1024,
            "a".repeat(64),
            capturedAt,
            createdAt);

    assertThat(asset.getDrawingSession()).isSameAs(session);
    assertThat(asset.getAssetType()).isEqualTo(DrawingAssetType.INTERMEDIATE);
    assertThat(asset.getAssetVersion()).isEqualTo(2);
    assertThat(asset.getStorageKey()).isEqualTo("2026/07/image.png");
    assertThat(asset.getMimeType()).isEqualTo("image/png");
    assertThat(asset.getFileSizeBytes()).isEqualTo(1024);
    assertThat(asset.getChecksumSha256()).isEqualTo("a".repeat(64));
    assertThat(asset.getCapturedAt()).isEqualTo(capturedAt);
    assertThat(asset.getCreatedAt()).isEqualTo(createdAt);
  }

  @Test
  void rejectsAssetTypeThatIsNotAcceptedBySnapshotUpload() {
    assertThatIllegalArgumentException()
        .isThrownBy(
            () ->
                DrawingAsset.snapshot(
                    mock(DrawingSession.class),
                    DrawingAssetType.DRAFT,
                    1,
                    "image.png",
                    "image/png",
                    1,
                    "a".repeat(64),
                    LocalDateTime.now(),
                    LocalDateTime.now()));
  }

  @Test
  void rejectsNonPositiveAssetVersion() {
    assertThatIllegalArgumentException()
        .isThrownBy(
            () ->
                DrawingAsset.snapshot(
                    mock(DrawingSession.class),
                    DrawingAssetType.FINAL,
                    0,
                    "image.png",
                    "image/png",
                    1,
                    "a".repeat(64),
                    LocalDateTime.now(),
                    LocalDateTime.now()));
  }
}
