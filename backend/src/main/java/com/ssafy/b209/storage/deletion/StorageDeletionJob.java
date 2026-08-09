package com.ssafy.b209.storage.deletion;

/**
 * 선점된 Storage 삭제 작업 한 건 (S15P11B209-780).
 *
 * <p>{@code storageKey} 는 아동 그림·음성 파일의 경로일 수 있다. 로그에 남기지 않는다(가드레일 9절) — 실패를 기록할 때도 id 와
 * resourceType 만 남긴다.
 *
 * @param id 잡 ID
 * @param storageKey 삭제 대상 Storage Key(프리픽스 미포함 상대 경로)
 * @param resourceType 어느 저장소에 속한 Key 인지 판별하는 유형
 * @param retryCount 지금까지의 재시도 횟수
 */
public record StorageDeletionJob(long id, String storageKey, String resourceType, int retryCount) {}
