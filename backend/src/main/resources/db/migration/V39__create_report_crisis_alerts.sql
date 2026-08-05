-- S15P11B209-902 위기 대응 안내를 리포트 버전 단위로 저장한다.
--
-- 보호자 가이드(report_parent_guides)와 다른 필드다. 가이드의 PROFESSIONAL_SUPPORT 는 상시 노출되는
-- 일반 상담 안내이고, 이쪽은 위기 신호가 있을 때만 생기는 사전 검토 템플릿이다. 문구·연락처를 섞으면
-- 평상시 안내에 신고 번호가 들어간다(계약 §4-4).
--
-- 행이 없으면 "위기 신호 없음"이다. ABUSE_DISCLOSURE 는 가해자가 보호자일 수 있어 자동 통지가 아이를
-- 위험하게 하므로 AI 가 이 값을 만들지 않는다 — 신호는 expertReviewRequired 로만 남는다(S15P11B209-889).
--
-- 리포트당 한 건이므로 report_id 를 PK 로 두어 중복을 구조로 막는다. 재생성은 새 reportVersion 을
-- 만들기 때문에(875 §1) 같은 리포트에 두 건이 생길 이유가 없다.

CREATE TABLE report_crisis_alerts (
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    reason_code VARCHAR(30) NOT NULL COMMENT '위기 사유 코드',
    severity VARCHAR(10) NOT NULL COMMENT '심각도',
    title VARCHAR(200) NOT NULL COMMENT '안내 제목',
    message TEXT NOT NULL COMMENT '안내 본문',
    CONSTRAINT pk_report_crisis_alerts PRIMARY KEY (report_id),
    CONSTRAINT fk_report_crisis_alerts_report_id FOREIGN KEY (report_id)
        REFERENCES reports (id) ON DELETE CASCADE,
    -- ABUSE_DISCLOSURE 는 목록에 두지 않는다. 저장 자체를 막아, 나중에 누가 매핑을 되돌려도
    -- 보호자 노출 경로로 새지 않는다(S15P11B209-890 에서 AI 측 반영 완료).
    CONSTRAINT ck_report_crisis_alerts_reason
        CHECK (reason_code IN ('SELF_HARM_RISK', 'CRISIS_INTENT')),
    CONSTRAINT ck_report_crisis_alerts_severity
        CHECK (severity IN ('HIGH', 'ELEVATED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='리포트 위기 대응 안내';

CREATE TABLE report_crisis_alert_steps (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '위기 안내 행동 단계 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    step_text TEXT NOT NULL COMMENT '보호자가 취할 행동',
    CONSTRAINT pk_report_crisis_alert_steps PRIMARY KEY (id),
    CONSTRAINT uk_report_crisis_alert_steps_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_crisis_alert_steps_report_id FOREIGN KEY (report_id)
        REFERENCES report_crisis_alerts (report_id) ON DELETE CASCADE,
    CONSTRAINT ck_report_crisis_alert_steps_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='위기 안내 행동 단계';

CREATE TABLE report_crisis_alert_resources (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '위기 안내 자원 ID',
    report_id BIGINT NOT NULL COMMENT '리포트 ID',
    display_order SMALLINT NOT NULL DEFAULT 0 COMMENT '노출 순서',
    resource_name VARCHAR(100) NOT NULL COMMENT '자원 이름',
    contact VARCHAR(100) NOT NULL COMMENT '연락처',
    note VARCHAR(300) NOT NULL DEFAULT '' COMMENT '보충 설명',
    CONSTRAINT pk_report_crisis_alert_resources PRIMARY KEY (id),
    CONSTRAINT uk_report_crisis_alert_resources_order UNIQUE (report_id, display_order),
    CONSTRAINT fk_report_crisis_alert_resources_report_id FOREIGN KEY (report_id)
        REFERENCES report_crisis_alerts (report_id) ON DELETE CASCADE,
    CONSTRAINT ck_report_crisis_alert_resources_order CHECK (display_order >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='위기 안내 상담·신고 자원';
