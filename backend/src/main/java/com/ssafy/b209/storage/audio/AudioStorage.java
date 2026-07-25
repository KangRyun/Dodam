package com.ssafy.b209.storage.audio;

/**
 * 음성 업로드를 임시 검증과 최종 보관으로 분리하는 저장 경계다.
 *
 * <p>임시 단계는 요청 fingerprint 계산 전까지 파일을 외부에 노출하지 않는다. 최종 승격 이후 DB 트랜잭션이 실패하면 {@link #delete(String)}로
 * 보상 삭제해야 한다.
 */
public interface AudioStorage {

  /**
   * 입력 Stream을 한 번만 소비해 실제 형식·길이·크기·checksum을 검증한 임시 파일로 저장한다.
   *
   * @param command 단일 소비 음성 업로드 명령
   * @return 아직 영구 key가 없는 검증 완료 임시 파일
   */
  StagedAudio stage(StoreAudioCommand command);

  /**
   * 검증된 임시 파일을 안전한 Root-relative key의 최종 파일로 원자 이동한다.
   *
   * @param stagedAudio {@link #stage(StoreAudioCommand)}가 반환한 임시 파일
   * @return DB에만 보관할 저장 key와 checksum 등 안전한 메타데이터
   */
  StoredAudio promote(StagedAudio stagedAudio);

  /**
   * 저장된 음성을 Storage Key로 조회한다.
   *
   * <p>반환된 Stream의 소유권은 호출자에게 있으며 사용 후 닫아야 한다.
   *
   * @param storageKey {@link #promote(StagedAudio)}가 반환한 상대 Storage Key
   * @return 음성 Stream과 HTTP 전송 Metadata
   */
  StoredAudioContent read(String storageKey);

  /**
   * 아직 승격되지 않은 임시 파일을 정리한다.
   *
   * @param stagedAudio 이 요청에서 생성한 임시 파일
   */
  void discard(StagedAudio stagedAudio);

  /**
   * DB 저장 실패 시 이번 요청의 최종 파일을 보상 삭제한다.
   *
   * @param storageKey 저장소가 생성한 Root-relative key
   */
  void delete(String storageKey);
}
