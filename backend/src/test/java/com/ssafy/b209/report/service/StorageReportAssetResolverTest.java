package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageErrorCode;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Optional;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 리포트 PDF 이미지 자산 조회 경계를 고정한다(S15P11B209-966).
 *
 * <p>핵심은 "그림 한 장 때문에 리포트 내보내기가 실패하지 않는다"다. 실을 수 없는 이미지는 조용히 빠지고, 실을 수 있는 이미지는 렌더러가 배치 비율을 계산할 수 있도록
 * 픽셀 크기까지 함께 나온다.
 */
@ExtendWith(MockitoExtension.class)
class StorageReportAssetResolverTest {

  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private ImageStorage imageStorage;
  @Mock private DrawingAsset drawingAsset;

  private StorageReportAssetResolver resolver;

  @BeforeEach
  void setUp() {
    resolver = new StorageReportAssetResolver(drawingAssetRepository, imageStorage);
  }

  @Test
  void readsPngBytesWithPixelDimensions() throws Exception {
    byte[] png = png(640, 480);
    givenStoredImage(png, "image/png");

    Optional<ReportImageAsset> asset = resolver.resolveDrawingImage(11L);

    assertThat(asset).isPresent();
    assertThat(asset.get().bytes()).isEqualTo(png);
    assertThat(asset.get().mimeType()).isEqualTo("image/png");
    assertThat(asset.get().widthPx()).isEqualTo(640);
    assertThat(asset.get().heightPx()).isEqualTo(480);
    assertThat(asset.get().aspectRatio()).isEqualTo(0.75);
  }

  @Test
  void readsJpegAsWell() throws Exception {
    givenStoredImage(jpeg(400, 400), "image/jpeg");

    assertThat(resolver.resolveDrawingImage(11L)).isPresent();
  }

  @Test
  void skipsFormatsThatPdfCannotEmbedDirectly() throws Exception {
    // 저장은 허용하지만 PDF 가 그대로 품을 수 없는 형식이다.
    givenStoredImage(png(320, 320), "image/webp");

    assertThat(resolver.resolveDrawingImage(11L)).isEmpty();
  }

  @Test
  void skipsImagesOverTheDocumentSizeLimit() throws Exception {
    byte[] png = png(320, 320);
    given(drawingAssetRepository.findById(11L)).willReturn(Optional.of(drawingAsset));
    given(drawingAsset.getStorageKey()).willReturn("images/a.png");
    given(imageStorage.read("images/a.png"))
        .willReturn(
            new StoredImageContent(new ByteArrayInputStream(png), "image/png", 9L * 1024 * 1024));

    assertThat(resolver.resolveDrawingImage(11L)).isEmpty();
  }

  @Test
  void skipsBytesThatAreNotAnImage() {
    byte[] garbage = "not an image".getBytes();
    given(drawingAssetRepository.findById(11L)).willReturn(Optional.of(drawingAsset));
    given(drawingAsset.getStorageKey()).willReturn("images/a.png");
    given(imageStorage.read("images/a.png"))
        .willReturn(
            new StoredImageContent(new ByteArrayInputStream(garbage), "image/png", garbage.length));

    assertThat(resolver.resolveDrawingImage(11L)).isEmpty();
  }

  @Test
  void returnsEmptyWhenTheAssetRowIsGone() {
    given(drawingAssetRepository.findById(404L)).willReturn(Optional.empty());

    assertThat(resolver.resolveDrawingImage(404L)).isEmpty();
    verifyNoInteractions(imageStorage);
  }

  @Test
  void keepsTheReportAliveWhenStorageReadFails() {
    given(drawingAssetRepository.findById(11L)).willReturn(Optional.of(drawingAsset));
    given(drawingAsset.getStorageKey()).willReturn("images/a.png");
    given(imageStorage.read("images/a.png"))
        .willThrow(new BusinessException(ImageStorageErrorCode.IMAGE_NOT_FOUND));

    // 예외가 밖으로 나가면 리포트 내보내기 전체가 실패한다.
    assertThat(resolver.resolveDrawingImage(11L)).isEmpty();
  }

  @Test
  void returnsEmptyWithoutTouchingStorageWhenThereIsNoAssetId() {
    assertThat(resolver.resolveDrawingImage(null)).isEmpty();
    verifyNoInteractions(drawingAssetRepository, imageStorage);
  }

  private void givenStoredImage(byte[] bytes, String contentType) {
    given(drawingAssetRepository.findById(11L)).willReturn(Optional.of(drawingAsset));
    given(drawingAsset.getStorageKey()).willReturn("images/a.png");
    given(imageStorage.read("images/a.png"))
        .willReturn(content(new ByteArrayInputStream(bytes), contentType, bytes.length));
  }

  private StoredImageContent content(InputStream stream, String contentType, long size) {
    return new StoredImageContent(stream, contentType, size);
  }

  private byte[] png(int width, int height) throws IOException {
    return encode(width, height, "png");
  }

  private byte[] jpeg(int width, int height) throws IOException {
    return encode(width, height, "jpg");
  }

  private byte[] encode(int width, int height, String format) throws IOException {
    BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    ImageIO.write(image, format, output);
    return output.toByteArray();
  }
}
