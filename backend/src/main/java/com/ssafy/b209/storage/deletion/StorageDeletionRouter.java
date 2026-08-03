package com.ssafy.b209.storage.deletion;

import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.image.ImageStorage;
import org.springframework.stereotype.Component;

/**
 * {@code resource_type} 을 실제 저장소로 연결한다 (S15P11B209-780).
 *
 * <p>⚠️ <b>유형별 라우팅이 필수인 이유.</b> 그림과 음성은 같은 버킷에 프리픽스로만 갈린다
 * ({@code dodam/images/…} · {@code dodam/audio/…}). 각 구현의 {@code delete(key)} 는 자기 프리픽스를 스스로 붙이므로,
 * 어느 인터페이스를 부르느냐가 곧 어느 폴더를 지우느냐다. 아무거나 부르면 엉뚱한 경로를 지운다.
 *
 * <p>⚠️ <b>모르는 유형을 성공으로 처리하지 않는 이유.</b> S3 {@code deleteObject} 는 없는 키에도 성공을 돌려준다. 잘못된 저장소로 보내면
 * 잡은 COMPLETED 로 사라지고 파일은 그대로 남는다 — "지웠다"는 거짓 기록만 남고 나중에 찾을 방법이 없다. 그래서 매핑이 없으면 실패로 남겨 드러나게 한다
 * (가드레일 9절).
 */
@Component
public class StorageDeletionRouter {

  /** 매핑이 없는 유형에 붙는 오류 코드. FAILED 목록에서 이 코드로 걸러 보면 된다. */
  public static final String UNMAPPED_RESOURCE_TYPE = "UNMAPPED_RESOURCE_TYPE";

  private final ImageStorage imageStorage;
  private final AudioStorage audioStorage;

  public StorageDeletionRouter(ImageStorage imageStorage, AudioStorage audioStorage) {
    this.imageStorage = imageStorage;
    this.audioStorage = audioStorage;
  }

  /**
   * 유형에 맞는 저장소에서 파일을 삭제한다.
   *
   * <p>⚠️ 트랜잭션 밖에서 호출해야 한다. 트랜잭션 안에서 부르면 이후 롤백 시 파일만 지워진 고아 상태가 된다.
   *
   * @param job 선점된 삭제 작업
   * @throws UnmappedResourceTypeException 매핑되지 않은 {@code resourceType}
   */
  public void delete(StorageDeletionJob job) {
    switch (job.resourceType()) {
      // 그림 관련 — 전부 이미지 저장소(dodam/images/…)
      case "DRAWING_ASSET", "CHILD_PROFILE_IMAGE", "COMMUNITY_ATTACHMENT" ->
          imageStorage.delete(job.storageKey());
      // 아이 발화 음성 — 음성 저장소(dodam/audio/…)
      case "CONVERSATION_AUDIO" -> audioStorage.delete(job.storageKey());
      // REPORT_PDF 는 의도적으로 매핑하지 않는다 (S15P11B209-780).
      //   리포트 PDF 를 저장하는 코드가 아직 없어(reports.pdf_storage_key 를 쓰는 곳이 없다)
      //   어느 프리픽스에 놓일지 정해지지 않았다. 추측해서 이미지 저장소로 보내면 위 주석의
      //   "거짓 COMPLETED" 가 된다. PDF 저장이 붙을 때 여기에 한 줄을 추가하고,
      //   그때 FAILED 로 남아 있던 잡을 PENDING 으로 되돌리면 밀린 것까지 처리된다.
      default -> throw new UnmappedResourceTypeException(job.resourceType());
    }
  }

  /** 매핑되지 않은 {@code resource_type} 을 만났을 때. 재시도해도 결과가 같으므로 즉시 실패로 확정한다. */
  public static class UnmappedResourceTypeException extends RuntimeException {
    public UnmappedResourceTypeException(String resourceType) {
      super("매핑되지 않은 resource_type: " + resourceType);
    }
  }
}
