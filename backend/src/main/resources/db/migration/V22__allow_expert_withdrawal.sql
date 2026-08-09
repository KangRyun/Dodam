-- 전문가 회원 탈퇴 허용 (S15P11B209-728)
--
-- 배경: 탈퇴 시 users 행을 지우면 expert_profiles.user_id 의 ON DELETE RESTRICT 에 걸려
--   DB 제약 위반이 500 으로 샜다. 전문가도 탈퇴할 수 있어야 한다는 결정에 따라 경로를 연다.
--
-- 막고 있던 것은 두 겹이었다.
--   ① users → expert_profiles          (RESTRICT) — 탈퇴 처리에서 프로필을 먼저 지워 해소
--   ② expert_profiles → activity_templates (RESTRICT) — 이 마이그레이션이 해소한다
--
-- 왜 자료를 지우지 않고 작성자만 끊나:
--   activity_templates 는 보호자에게 제공되는 **콘텐츠**다. 작성자가 떠났다고 자료까지
--   사라지면 남은 사용자가 보던 것이 없어진다. community_posts.author_user_id 를
--   ON DELETE SET NULL 로 둔 것과 같은 판단이다 — 콘텐츠는 남기고 작성자만 비식별화한다.
--
-- 지금 바꾸는 이유:
--   이 테이블은 아직 Java 코드가 없다(스키마만 존재). 데이터도 이관할 것이 없으므로
--   비용이 가장 싼 시점이다. 기능 구현 후에는 NOT NULL 을 푸는 데 데이터 정리가 따라붙는다.
--
-- ⚠️ 후속: expert_profile_id 를 읽는 코드를 쓸 때 NULL 을 다뤄야 한다.
--   NULL = "작성자가 탈퇴한 자료". 화면에서는 작성자 없이 표시하거나 숨기는 정책이 필요하다.

ALTER TABLE activity_templates
    DROP FOREIGN KEY fk_activity_templates_expert_profile_id;

ALTER TABLE activity_templates
    MODIFY COLUMN expert_profile_id BIGINT NULL COMMENT '전문가 프로필 ID (NULL = 작성자 탈퇴)';

ALTER TABLE activity_templates
    ADD CONSTRAINT fk_activity_templates_expert_profile_id FOREIGN KEY (expert_profile_id)
        REFERENCES expert_profiles (id) ON DELETE SET NULL;
