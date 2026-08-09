package com.ssafy.b209.storage.image;

/**
 * 이미지 저장이 완료된 뒤 도메인 서비스가 사용하는 검증된 Metadata다.
 *
 * <p>{@code storageKey}는 Storage Root를 제외한 상대 Key이며, 서버 내부 절대 경로나 임시 파일 정보는 포함하지 않는다. 이미지 크기는 실제
 * 저장된 파일 Header에서 읽은 값을 사용한다.
 *
 * @param storageKey Storage Root 기준 상대 Key
 * @param storedFileName 검증된 형식과 UUID로 생성한 파일명
 * @param contentType 실제 이미지 Signature로 검증한 MIME Type
 * @param size 실제 저장한 이미지 크기(Byte)
 * @param checksumSha256 실제 이미지 Byte의 SHA-256 Hex
 * @param widthPx 이미지 Header에서 확인한 너비(px)
 * @param heightPx 이미지 Header에서 확인한 높이(px)
 */
public record StoredImage(
    String storageKey,
    String storedFileName,
    String contentType,
    long size,
    String checksumSha256,
    Integer widthPx,
    Integer heightPx) {

  /**
   * 이미지 크기를 제공하지 않는 기존 Storage Adapter와 테스트에서 사용하는 호환 생성자다.
   *
   * <p>신규 저장 구현은 크기를 포함한 canonical constructor를 사용해야 한다.
   *
   * @param storageKey Storage Root 기준 상대 Key
   * @param storedFileName 검증된 형식과 UUID로 생성한 파일명
   * @param contentType 실제 이미지 Signature로 검증한 MIME Type
   * @param size 실제 저장한 이미지 크기(Byte)
   * @param checksumSha256 실제 이미지 Byte의 SHA-256 Hex
   */
  public StoredImage(
      String storageKey,
      String storedFileName,
      String contentType,
      long size,
      String checksumSha256) {
    this(storageKey, storedFileName, contentType, size, checksumSha256, null, null);
  }
}
