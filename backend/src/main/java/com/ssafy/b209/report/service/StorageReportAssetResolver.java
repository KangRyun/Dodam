package com.ssafy.b209.report.service;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Iterator;
import java.util.Optional;
import java.util.Set;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 저장소에서 그림 바이트를 읽어 리포트 PDF 용 이미지로 만든다.
 *
 * <p>실을 수 없는 이미지는 조용히 빼고 리포트는 계속 만든다. 판단 기준은 세 가지다.
 *
 * <ul>
 *   <li><b>형식</b> — PDF 가 그대로 품을 수 있는 PNG·JPEG 만 싣는다. WebP·GIF 는 변환이 필요해 제외한다
 *   <li><b>용량</b> — 상한을 넘는 파일은 싣지 않는다. 리포트 하나에 그림이 여러 장 들어가므로 한 장이 크면 문서 전체가 무거워진다
 *   <li><b>실제 이미지 여부</b> — 헤더를 읽어 픽셀 크기를 확인한다. 크기를 모르면 렌더러가 배치 비율을 계산할 수 없다
 * </ul>
 */
@Component
public class StorageReportAssetResolver implements ReportAssetResolver {

  private static final Logger log = LoggerFactory.getLogger(StorageReportAssetResolver.class);

  /** PDF 에 변환 없이 실을 수 있는 형식이다. */
  private static final Set<String> EMBEDDABLE_MIME_TYPES =
      Set.of("image/png", "image/jpeg", "image/jpg");

  /**
   * 그림 한 장의 용량 상한이다.
   *
   * <p>리포트에는 HTP 세 장까지 들어갈 수 있어 상한을 낮게 잡는다. 저장 단계에서 이미 크기를 검증하지만, 그때 기준은 화면 표시용이라 문서용 상한을 따로 둔다.
   */
  private static final long MAX_IMAGE_BYTES = 8L * 1024 * 1024;

  private final DrawingAssetRepository drawingAssetRepository;
  private final ImageStorage imageStorage;

  /**
   * 리포트 이미지 자산 조회 경계를 구성한다.
   *
   * @param drawingAssetRepository 그림 파일의 저장 Key 조회 경계
   * @param imageStorage 저장된 이미지를 읽는 경계
   */
  public StorageReportAssetResolver(
      DrawingAssetRepository drawingAssetRepository, ImageStorage imageStorage) {
    this.drawingAssetRepository = drawingAssetRepository;
    this.imageStorage = imageStorage;
  }

  @Override
  public Optional<ReportImageAsset> resolveDrawingImage(Long drawingAssetId) {
    if (drawingAssetId == null) return Optional.empty();
    try {
      DrawingAsset asset = drawingAssetRepository.findById(drawingAssetId).orElse(null);
      if (asset == null) {
        log.info("리포트 PDF 그림을 찾을 수 없습니다. drawingAssetId={}", drawingAssetId);
        return Optional.empty();
      }
      return read(drawingAssetId, asset.getStorageKey());
    } catch (RuntimeException exception) {
      // 그림 한 장 때문에 리포트를 못 만들게 하지 않는다. 원인은 로그로 남긴다.
      log.warn(
          "리포트 PDF 그림을 읽지 못했습니다. drawingAssetId={}, exceptionType={}",
          drawingAssetId,
          exception.getClass().getName());
      return Optional.empty();
    }
  }

  private Optional<ReportImageAsset> read(Long drawingAssetId, String storageKey) {
    try (StoredImageContent content = imageStorage.read(storageKey)) {
      String mimeType = content.contentType().toLowerCase();
      if (!EMBEDDABLE_MIME_TYPES.contains(mimeType)) {
        log.info(
            "리포트 PDF 에 실을 수 없는 형식입니다. drawingAssetId={}, mimeType={}", drawingAssetId, mimeType);
        return Optional.empty();
      }
      if (content.size() > MAX_IMAGE_BYTES) {
        log.info(
            "리포트 PDF 그림이 용량 상한을 넘었습니다. drawingAssetId={}, size={}", drawingAssetId, content.size());
        return Optional.empty();
      }
      byte[] bytes = content.inputStream().readAllBytes();
      int[] dimensions = readDimensions(bytes);
      if (dimensions == null) {
        log.warn("리포트 PDF 그림의 픽셀 크기를 읽지 못했습니다. drawingAssetId={}", drawingAssetId);
        return Optional.empty();
      }
      return Optional.of(new ReportImageAsset(bytes, mimeType, dimensions[0], dimensions[1]));
    } catch (IOException exception) {
      log.warn("리포트 PDF 그림 Stream 을 읽지 못했습니다. drawingAssetId={}", drawingAssetId);
      return Optional.empty();
    }
  }

  /**
   * 헤더만 읽어 픽셀 크기를 얻는다.
   *
   * <p>전체를 디코딩하면 큰 그림에서 메모리를 그만큼 잡는다. 읽는 데 실패하면 이미지가 아니거나 깨진 파일이라는 뜻이므로 싣지 않는다.
   *
   * @return {@code [가로, 세로]} 이며 읽을 수 없으면 {@code null}
   */
  private int[] readDimensions(byte[] bytes) throws IOException {
    try (ImageInputStream stream =
        ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
      if (stream == null) return null;
      Iterator<ImageReader> readers = ImageIO.getImageReaders(stream);
      if (!readers.hasNext()) return null;
      ImageReader reader = readers.next();
      try {
        reader.setInput(stream);
        return new int[] {reader.getWidth(0), reader.getHeight(0)};
      } finally {
        reader.dispose();
      }
    }
  }
}
