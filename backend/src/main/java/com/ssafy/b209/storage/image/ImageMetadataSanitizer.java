package com.ssafy.b209.storage.image;

import com.drew.imaging.ImageMetadataReader;
import com.drew.imaging.ImageProcessingException;
import com.drew.metadata.MetadataException;
import com.drew.metadata.exif.ExifIFD0Directory;
import com.ssafy.b209.global.exception.BusinessException;
import java.awt.Graphics2D;
import java.awt.Transparency;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Iterator;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageOutputStream;

/**
 * 업로드 이미지의 표시 방향을 픽셀에 반영한 뒤 개인정보가 포함될 수 있는 Metadata 없이 다시 인코딩한다.
 *
 * <p>JPEG의 EXIF Orientation과 PNG의 eXIf Orientation을 먼저 읽고, 재인코딩 결과에는 원본 EXIF·XMP·IPTC 및 PNG 텍스트 청크를
 * 전달하지 않는다. 호출자는 정제 후 파일의 크기와 Checksum을 다시 계산해야 한다.
 */
final class ImageMetadataSanitizer {

  private static final float JPEG_QUALITY = 0.95F;

  private ImageMetadataSanitizer() {}

  /**
   * 이미지 파일을 Metadata가 제거된 동일 형식의 파일로 원자적으로 교체한다.
   *
   * @param imageFile 정제할 임시 이미지 파일
   * @param formatName {@link ImageIO}가 사용하는 출력 형식명
   * @throws BusinessException 이미지 디코딩이 불가능하거나 정제 파일을 안전하게 저장할 수 없는 경우
   */
  static void sanitize(Path imageFile, String formatName) {
    int orientation = readOrientation(imageFile);
    BufferedImage source = readImage(imageFile);
    BufferedImage normalized = applyOrientation(source, orientation, "jpeg".equals(formatName));
    Path sanitizedFile = null;
    try {
      sanitizedFile = Files.createTempFile(imageFile.getParent(), ".sanitized-", ".tmp");
      writeWithoutMetadata(normalized, sanitizedFile, formatName);
      replace(imageFile, sanitizedFile);
      sanitizedFile = null;
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | SecurityException exception) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED, exception);
    } finally {
      deleteQuietly(sanitizedFile);
    }
  }

  private static int readOrientation(Path imageFile) {
    try {
      var metadata = ImageMetadataReader.readMetadata(imageFile.toFile());
      ExifIFD0Directory directory = metadata.getFirstDirectoryOfType(ExifIFD0Directory.class);
      if (directory == null || !directory.containsTag(ExifIFD0Directory.TAG_ORIENTATION)) {
        return 1;
      }
      int orientation = directory.getInt(ExifIFD0Directory.TAG_ORIENTATION);
      return orientation >= 1 && orientation <= 8 ? orientation : 1;
    } catch (ImageProcessingException
        | MetadataException
        | IOException
        | RuntimeException ignored) {
      // Metadata가 손상돼도 픽셀 디코딩이 가능하면 재인코딩 과정에서 원본 Metadata를 제거한다.
      return 1;
    }
  }

  private static BufferedImage readImage(Path imageFile) {
    try {
      BufferedImage image = ImageIO.read(imageFile.toFile());
      if (image == null || image.getWidth() <= 0 || image.getHeight() <= 0) {
        throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
      }
      return image;
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | RuntimeException exception) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE, exception);
    }
  }

  private static BufferedImage applyOrientation(
      BufferedImage source, int orientation, boolean forceOpaque) {
    int sourceWidth = source.getWidth();
    int sourceHeight = source.getHeight();
    boolean swapsDimensions = orientation >= 5 && orientation <= 8;
    int targetWidth = swapsDimensions ? sourceHeight : sourceWidth;
    int targetHeight = swapsDimensions ? sourceWidth : sourceHeight;
    boolean hasAlpha =
        !forceOpaque && source.getColorModel().getTransparency() != Transparency.OPAQUE;
    BufferedImage target =
        new BufferedImage(
            targetWidth,
            targetHeight,
            hasAlpha ? BufferedImage.TYPE_INT_ARGB : BufferedImage.TYPE_INT_RGB);
    Graphics2D graphics = target.createGraphics();
    try {
      graphics.drawImage(
          source, orientationTransform(orientation, sourceWidth, sourceHeight), null);
    } finally {
      graphics.dispose();
    }
    return target;
  }

  private static AffineTransform orientationTransform(int orientation, int width, int height) {
    return switch (orientation) {
      case 2 -> new AffineTransform(-1, 0, 0, 1, width, 0);
      case 3 -> new AffineTransform(-1, 0, 0, -1, width, height);
      case 4 -> new AffineTransform(1, 0, 0, -1, 0, height);
      case 5 -> new AffineTransform(0, 1, 1, 0, 0, 0);
      case 6 -> new AffineTransform(0, 1, -1, 0, height, 0);
      case 7 -> new AffineTransform(0, -1, -1, 0, height, width);
      case 8 -> new AffineTransform(0, -1, 1, 0, 0, width);
      default -> new AffineTransform();
    };
  }

  private static void writeWithoutMetadata(BufferedImage image, Path outputFile, String formatName)
      throws IOException {
    Iterator<ImageWriter> writers = ImageIO.getImageWritersByFormatName(formatName);
    if (!writers.hasNext()) {
      throw new BusinessException(ImageStorageErrorCode.INVALID_IMAGE_FILE);
    }
    ImageWriter writer = writers.next();
    try (ImageOutputStream output = ImageIO.createImageOutputStream(outputFile.toFile())) {
      if (output == null) {
        throw new BusinessException(ImageStorageErrorCode.IMAGE_STORAGE_FAILED);
      }
      writer.setOutput(output);
      ImageWriteParam parameters = writer.getDefaultWriteParam();
      if ("jpeg".equals(formatName) && parameters.canWriteCompressed()) {
        parameters.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
        parameters.setCompressionQuality(JPEG_QUALITY);
      }
      writer.write(null, new IIOImage(image, null, null), parameters);
    } finally {
      writer.dispose();
    }
  }

  private static void replace(Path imageFile, Path sanitizedFile) throws IOException {
    try {
      Files.move(
          sanitizedFile,
          imageFile,
          StandardCopyOption.REPLACE_EXISTING,
          StandardCopyOption.ATOMIC_MOVE);
    } catch (AtomicMoveNotSupportedException ignored) {
      Files.move(sanitizedFile, imageFile, StandardCopyOption.REPLACE_EXISTING);
    }
  }

  private static void deleteQuietly(Path file) {
    if (file == null) {
      return;
    }
    try {
      Files.deleteIfExists(file);
    } catch (IOException | SecurityException ignored) {
      // 원본 임시 파일 처리 결과를 정제 중간 파일 삭제 실패로 가리지 않는다.
    }
  }
}
