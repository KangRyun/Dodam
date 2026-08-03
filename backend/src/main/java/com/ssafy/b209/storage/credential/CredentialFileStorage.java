package com.ssafy.b209.storage.credential;

import com.ssafy.b209.global.exception.BusinessException;

/** PDF와 이미지 자격 증빙을 보호된 Storage에 저장하는 외부 시스템 경계다. */
public interface CredentialFileStorage {

  /**
   * 파일 Signature와 크기를 검증한 뒤 내부 Storage에 저장한다.
   *
   * @param command 파일 Byte와 선언 Metadata
   * @return DB에 저장할 상대 Key와 검증 Metadata
   * @throws BusinessException 파일이 유효하지 않거나 저장에 실패한 경우
   */
  StoredCredentialFile store(StoreCredentialFileCommand command);

  /**
   * DB 저장 실패 시 보상 처리하거나 검토 전 자격을 삭제할 때 파일을 제거한다.
   *
   * @param storageKey {@link #store(StoreCredentialFileCommand)}가 반환한 상대 Key
   * @throws BusinessException Key가 안전하지 않거나 삭제에 실패한 경우
   */
  void delete(String storageKey);
}
