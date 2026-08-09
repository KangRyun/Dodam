-- 아이가 고른 답이 아직 글로 옮겨지지 않은 음성 답을 대신할 수 있게 한다.
--
-- 문제는 타이밍이었다. 질문이 뜨면 앱이 자동으로 녹음을 시작하는데, 조용한 방에서는
-- 무음이 그대로 답으로 올라간다. 그 답의 STT 는 몇 초간 PENDING 이고, **그 창 안에서
-- 아이가 보기를 고르면 "이미 답이 있다"며 거절됐다.** 아이가 실제로 고른 답이 기록에
-- 남지 않았다(2026-08-08 태블릿 실행에서 확인).
--
-- ⚠️ 대신하는 것은 **아직 글이 없는 음성 답(PENDING·PROCESSING)뿐**이다.
--    STT 가 SUCCESS 로 끝난 답은 아이가 실제로 말한 말이라 보기로 덮지 않는다.
--    FAILED 는 이미 중복 판정에서 빠져 있어 이 경로가 필요 없다.
--
-- ⚠️ 지우지 않는다. 아동 기록에서 무엇이 언제 왜 물러났는지는 되짚을 수 있어야 한다.
--    조회하는 쪽이 superseded_at IS NULL 로 거른다 — 지우면 되짚을 방법이 사라진다.

ALTER TABLE conversation_messages
    ADD COLUMN superseded_at DATETIME(6) NULL
        COMMENT '뒤에 온 명시적 답에 자리를 내준 시각. NULL 이면 살아 있는 답' AFTER is_skipped,
    ADD COLUMN superseded_by_message_id BIGINT NULL
        COMMENT '자리를 대신한 답 메시지 ID' AFTER superseded_at;

-- 둘은 함께 채워지거나 함께 비어야 한다. 한쪽만 있으면 "누가 대신했는지 모르는 퇴장"이
-- 되어 감사할 수 없다.
--
-- ⚠️ FK 를 걸지 않는다. MySQL 8 은 `ON DELETE SET NULL` FK 가 걸린 컬럼에 CHECK 를
--    허용하지 않는다(Error 3823) — 삭제가 CHECK 를 깨뜨릴 수 있기 때문이다. 둘 중
--    하나만 가질 수 있어 **CHECK 를 택했다.** FK 를 택하면 참조된 메시지가 지워질 때
--    superseded_by_message_id 만 NULL 이 되어, superseded_at 은 남고 "누가 대신했는지
--    모르는 퇴장"이 생긴다. 그건 이 컬럼을 두는 이유를 정확히 무너뜨린다.
--
--    참조 무결성은 실무상 유지된다 — 메시지는 개별 삭제되지 않고 세션이 지워질 때
--    conversation_messages 가 통째로 CASCADE 로 함께 사라진다.
ALTER TABLE conversation_messages
    ADD CONSTRAINT ck_conversation_messages_supersede_pair
        CHECK ((superseded_at IS NULL AND superseded_by_message_id IS NULL)
            OR (superseded_at IS NOT NULL AND superseded_by_message_id IS NOT NULL));

CREATE INDEX idx_conversation_messages_live_answer
    ON conversation_messages (parent_message_id, superseded_at);
