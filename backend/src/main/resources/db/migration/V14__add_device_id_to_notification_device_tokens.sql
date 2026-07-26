-- NOTI-01·NOTI-02(S15P11B209-549·550) 지원: 클라이언트 설치 식별자로 기기 Token을 upsert·해제한다.
--
-- 기존 스키마는 token_hash만 UNIQUE라서 같은 기기가 Token을 갱신하면 이전 행을 찾을 수 없었다.
-- 명세 15.2는 동일 deviceId를 upsert하고 NOTI-02는 {deviceId}로 해제하므로 설치 식별자가 필요하다.
--
-- token_hash UNIQUE는 유지한다. 같은 Token이 다른 계정에 중복 등록되어 알림이 잘못 배달되는 것을 막는다.
-- app_version은 명세 15.2 요청 필드이며 저장할 곳이 없으면 받고 버리는 거짓 계약이 되므로 함께 추가한다.

ALTER TABLE notification_device_tokens
    ADD COLUMN device_id VARCHAR(100) NOT NULL COMMENT '클라이언트 설치 식별자' AFTER user_id,
    ADD COLUMN app_version VARCHAR(20) NULL COMMENT '등록 시점 앱 버전' AFTER push_provider,
    ADD CONSTRAINT uk_notification_device_tokens_user_device UNIQUE (user_id, device_id);
