-- 보호자 PIN (S15P11B209-879)
--
-- 아동 모드에서 보호자 홈으로 복귀할 때 요구하는 4자리 PIN 을 보관한다.
--
-- 왜 users 에 컬럼을 붙이지 않는가: 인증 자료를 프로필 테이블과 섞지 않는다. users 는 이미 넓고,
-- PIN 은 조회 빈도·수명·민감도가 다르다. user_id 를 PK 로 두어 "보호자 계정당 PIN 하나"를
-- 애플리케이션 규칙이 아니라 구조로 보장한다 — 아이별 PIN 은 만들지 않는다.
--
-- pin_hash 는 pepper(HMAC-SHA256) 를 거친 값을 BCrypt 로 해시한 결과다. PIN 원문은 어디에도
-- 저장하지 않는다. 4자리는 조합이 10,000개뿐이라 DB 만 유출돼도 전수 시도가 가능한데,
-- pepper 키는 DB 밖(시크릿)에 있어 해시만으로는 복원할 수 없다.
--
-- lockout_level 은 지수 백오프 단계다. 5회 실패마다 한 단계 올라가고 잠금 시간이 길어진다
-- (30초 → 1분 → 5분 → 15분 → 1시간). 검증 성공 시 0으로 되돌린다. 고정 30초만 쓰면 분당 약
-- 10회 시도가 가능해 10,000개 조합을 하루 안에 훑을 수 있다.
CREATE TABLE user_guardian_pins (
    user_id BIGINT NOT NULL COMMENT '보호자 사용자 ID',
    pin_hash VARCHAR(255) NOT NULL COMMENT 'pepper 적용 후 BCrypt 해시. 원문 저장 금지',
    hash_algorithm VARCHAR(30) NOT NULL COMMENT '해시 알고리즘 식별자',
    failed_attempt_count INT NOT NULL DEFAULT 0 COMMENT '연속 검증 실패 횟수',
    lockout_level INT NOT NULL DEFAULT 0 COMMENT '지수 백오프 단계이며 성공 시 0으로 초기화',
    locked_until DATETIME(6) NULL COMMENT '잠금 해제 시각(UTC)이며 잠금 중이 아니면 NULL',
    last_verified_at DATETIME(6) NULL COMMENT '마지막 검증 성공 시각(UTC)',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_user_guardian_pins PRIMARY KEY (user_id),
    CONSTRAINT fk_user_guardian_pins_user_id FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_user_guardian_pins_counters
        CHECK (failed_attempt_count >= 0 AND lockout_level >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='보호자 PIN';
