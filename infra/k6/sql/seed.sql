-- ============================================================================
-- k6 부하 테스트용 합성 계정 시드 (S15P11B209-354)
--
-- ⚠️ 실아동 데이터 사용 금지(가드레일 9절). 부하 테스트는 오직 이 스크립트가 만든
--    합성 계정만 사용한다. 모든 행은 닉네임 접두 'k6-load-' 로 식별되며,
--    cleanup.sql 은 그 접두만 지운다 — 실데이터와 섞이지 않게 하는 유일한 안전장치다.
--    ★ 이 접두를 바꾸려면 cleanup.sql 도 같이 바꿔야 한다.
--
-- 왜 아동을 여러 명 만드나:
--    백엔드는 **아동당 진행 중 그림 세션을 1개만** 허용한다(POST /drawing-sessions → 409).
--    VU 하나가 아동 하나를 전담해야 해서, 목표 VU 이상으로 아동이 필요하다.
--    기본 30명 = 355 의 계획 최대 VU(30) 기준.
--
-- 실행 (서버에서):
--   docker exec -i dodam-mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" dodam < sql/seed.sql
--   ※ 비밀번호를 셸에 직접 적지 말 것. 컨테이너 환경변수를 그대로 참조한다.
--
-- 멱등: 두 번 실행해도 중복 생성되지 않는다(NOT EXISTS / LIKE 로 방어).
-- ============================================================================

SET @child_count = 30;   -- 목표 최대 VU 이상으로 잡을 것

START TRANSACTION;

-- ── 합성 보호자 1명 ─────────────────────────────────────────────────────────
-- auth_accounts(소셜 연결)는 만들지 않는다. 토큰을 오프라인 발급하므로 필요 없고,
-- 실제 소셜 계정과 충돌할 여지도 없앤다.
INSERT INTO users (role, nickname, account_status, is_completed)
SELECT 'GUARDIAN', 'k6-load-guardian', 'ACTIVE', TRUE
WHERE NOT EXISTS (SELECT 1 FROM users WHERE nickname = 'k6-load-guardian');

SET @guardian_id = (SELECT id FROM users WHERE nickname = 'k6-load-guardian' LIMIT 1);

-- ── 합성 아동 N명 ───────────────────────────────────────────────────────────
-- MySQL 8 재귀 CTE 로 번호를 만든다(프로시저 없이 반복 INSERT).
INSERT INTO children (nickname, birth_date, question_difficulty, tutorial_status, profile_status)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < @child_count
)
SELECT
    CONCAT('k6-load-child-', LPAD(seq.n, 3, '0')),
    '2019-05-01',
    'PRESCHOOL',
    'COMPLETED',
    'ACTIVE'
FROM seq
WHERE NOT EXISTS (
    SELECT 1 FROM children c WHERE c.nickname = CONCAT('k6-load-child-', LPAD(seq.n, 3, '0'))
);

-- ── 보호자-아동 연결 ────────────────────────────────────────────────────────
-- 이 관계가 없으면 모든 조회가 403/404 다 — 인가가 관계 기반이기 때문이다.
INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type)
SELECT @guardian_id, c.id, 'GUARDIAN'
FROM children c
WHERE c.nickname LIKE 'k6-load-child-%'
  AND NOT EXISTS (
      SELECT 1 FROM guardian_child_relations r
      WHERE r.guardian_user_id = @guardian_id AND r.child_id = c.id
  );

COMMIT;

-- ── 출력: k6 에 넘길 값 ─────────────────────────────────────────────────────
SELECT @guardian_id AS guardian_user_id;

SELECT GROUP_CONCAT(id ORDER BY id) AS child_ids
FROM children
WHERE nickname LIKE 'k6-load-child-%';

SELECT COUNT(*) AS seeded_children FROM children WHERE nickname LIKE 'k6-load-child-%';
