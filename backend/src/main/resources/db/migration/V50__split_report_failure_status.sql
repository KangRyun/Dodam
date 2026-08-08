-- 리포트 실패를 "다시 해볼 수 있는 실패"와 "다시 해도 같은 실패"로 가른다.
--
-- 활동 완료와 리포트 생성을 떼어 놓으면서 생긴 자리다. 예전에는 리포트가 실패하면 활동
-- 자체가 FAILED 로 내려가 아이 화면에 "활동을 마무리하지 못했어요"가 떴다. 이제 활동은
-- 완료된 채로 남고, 리포트만 자기 상태를 들고 간다 — 그러려면 그 상태가 "다시 시도할
-- 값어치가 있는가"를 말할 수 있어야 한다.
--
--   FAILED_RETRYABLE  상류 장애·타임아웃처럼 다시 하면 될 수 있는 실패. 재시도 대상이다.
--   FAILED_FINAL      근거 부족·응답 계약 위반처럼 다시 해도 같은 실패. 재시도하지 않는다.
--
-- ⚠️ 기존 FAILED 행은 그대로 둔다. 어느 쪽이었는지 지금 와서는 알 수 없고, 짐작해 나누면
--    되돌릴 수 없는 오분류가 된다. 읽는 쪽이 FAILED 를 '재시도 판단 불가'로 다룬다.

ALTER TABLE reports
    DROP CHECK ck_reports_status;

ALTER TABLE reports
    ADD CONSTRAINT ck_reports_status
        CHECK (report_status IN (
            'GENERATING', 'COMPLETED', 'FAILED', 'HIDDEN',
            'FAILED_RETRYABLE', 'FAILED_FINAL'));

-- 재시도 대기열. 별도 표를 두는 이유는 **재시도가 리포트 상태와 수명이 다르기** 때문이다.
-- 리포트는 결국 성공하거나 최종 실패로 끝나지만, 그 사이 몇 번 시도했고 다음에 언제 다시
-- 할지는 그 행이 들고 있을 값이 아니다.
CREATE TABLE report_generation_retries (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '재시도 작업 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    analysis_id BIGINT NOT NULL COMMENT '최종 분석 ID',
    attempt_count SMALLINT NOT NULL DEFAULT 0 COMMENT '지금까지 시도한 횟수',
    next_attempt_at DATETIME(6) NOT NULL COMMENT '다음 시도 예정 시각',
    last_failure_stage VARCHAR(40) NULL COMMENT '마지막 실패 단계(AI 호출·응답 검증·저장)',
    last_failure_code VARCHAR(100) NULL COMMENT '마지막 실패 분류 코드',
    correlation_id CHAR(36) NULL COMMENT '요청을 로그와 잇는 식별자',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '등록 일시',
    resolved_at DATETIME(6) NULL COMMENT '성공하거나 포기한 시각',
    CONSTRAINT pk_report_generation_retries PRIMARY KEY (id),
    CONSTRAINT uk_report_generation_retries_report UNIQUE (report_id),
    CONSTRAINT fk_report_generation_retries_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    CONSTRAINT ck_report_generation_retries_attempts CHECK (attempt_count >= 0),
    INDEX idx_report_generation_retries_due (resolved_at, next_attempt_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 생성 재시도 대기열';
