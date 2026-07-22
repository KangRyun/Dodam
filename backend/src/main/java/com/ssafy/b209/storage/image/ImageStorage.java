package com.ssafy.b209.storage.image;

import com.ssafy.b209.global.exception.BusinessException;

/**
 * HTTP 전송 방식과 무관하게 이미지 데이터를 영속 Storage에 저장하는 경계다.
 *
 * <p>호출자는 {@link #store(StoreImageCommand)} 호출 시 입력 Stream의 소유권을 구현체에 넘긴다. 구현체는 Stream을 한 번만 소비하고
 * 성공 또는 실패 후 닫아야 하므로 호출자는 반환 이후 Stream을 재사용해서는 안 된다.
 */
public interface ImageStorage {

  /**
   * 이미지의 크기와 형식을 검증한 뒤 저장하고 외부에 노출해도 안전한 상대 Key를 반환한다.
   *
   * @param command 이미지 Stream과 검증에 필요한 Metadata
   * @return 절대 경로를 포함하지 않는 저장 결과
   * @throws BusinessException 이미지가 유효하지 않거나 안전하게 저장할 수 없는 경우
   */
  StoredImage store(StoreImageCommand command);
}
