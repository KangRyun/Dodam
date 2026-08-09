-- ============================================================================
-- k6 합성 데이터 정리 (S15P11B209-354)
--
-- ⚠️ 삭제 스크립트다. 실행 전에 반드시 아래 "① 확인" 구간만 먼저 돌려
--    지워질 행 수가 예상과 맞는지 눈으로 본다. 숫자를 보지 않고 지우지 않는다.
--
-- 범위: 닉네임 접두 'k6-load-' 인 합성 보호자·아동과 그들에게 매달린 것들만.
--    실아동 데이터는 이 조건에 절대 걸리지 않는다 — 접두를 바꾸지 말 것.
--
-- 삭제 순서가 중요하다. RESTRICT FK 가 걸린 곳이 있어서 자식부터 지워야 한다:
--    complaints → reports → analyses → htp_assessments → drawing_sessions → children
--    (그 외 대부분은 ON DELETE CASCADE 라 부모만 지우면 따라 지워진다)
--
-- 실행 (서버에서):
--   kubectl -n dodam exec -i sts/mysql -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot b209' < sql/cleanup.sql
--
-- ⚠️ MinIO 잔여 객체는 이 스크립트가 지우지 않는다. DB 행만 지운다.
--    업로드 시나리오를 돌렸다면 README 의 "MinIO 잔여 확인" 절차를 함께 수행한다.
-- ============================================================================

-- ── ① 확인 (지우기 전에 여기서 멈춰서 숫자를 볼 것) ────────────────────────
SELECT 'children' AS target, COUNT(*) AS rows_to_delete
FROM children WHERE nickname LIKE 'k6-load-child-%'
UNION ALL
SELECT 'users', COUNT(*) FROM users WHERE nickname = 'k6-load-guardian'
UNION ALL
SELECT 'drawing_sessions', COUNT(*) FROM drawing_sessions ds
JOIN children c ON c.id = ds.child_id WHERE c.nickname LIKE 'k6-load-child-%'
UNION ALL
SELECT 'reports', COUNT(*) FROM reports r
JOIN drawing_sessions ds ON ds.id = r.drawing_session_id
JOIN children c ON c.id = ds.child_id WHERE c.nickname LIKE 'k6-load-child-%';

-- ── ② 삭제 ─────────────────────────────────────────────────────────────────
START TRANSACTION;

CREATE TEMPORARY TABLE k6_children (id BIGINT PRIMARY KEY);
INSERT INTO k6_children SELECT id FROM children WHERE nickname LIKE 'k6-load-child-%';

CREATE TEMPORARY TABLE k6_sessions (id BIGINT PRIMARY KEY);
INSERT INTO k6_sessions
SELECT ds.id FROM drawing_sessions ds JOIN k6_children k ON k.id = ds.child_id;

CREATE TEMPORARY TABLE k6_reports (id BIGINT PRIMARY KEY);
INSERT INTO k6_reports
SELECT r.id FROM reports r JOIN k6_sessions s ON s.id = r.drawing_session_id;

CREATE TEMPORARY TABLE k6_analyses (id BIGINT PRIMARY KEY);
INSERT INTO k6_analyses
SELECT a.id FROM analyses a JOIN k6_sessions s ON s.id = a.drawing_session_id;

-- complaints 는 reports 를 RESTRICT 로 잡는다. 합성 리포트가 신고될 일은 없지만
-- 남아 있으면 아래 reports 삭제가 통째로 막히므로 먼저 끊는다.
DELETE FROM complaints WHERE target_report_id IN (SELECT id FROM k6_reports);

-- HTP 는 두 테이블로 나뉜다. drawing_sessions 를 RESTRICT 로 잡는 쪽은
-- htp_assessments 가 아니라 **htp_assessment_steps.drawing_session_id** 다.
-- steps 를 먼저 끊지 않으면 아래 drawing_sessions 삭제가 통째로 막힌다.
DELETE FROM htp_assessment_steps
WHERE drawing_session_id IN (SELECT id FROM k6_sessions)
   OR htp_assessment_id IN (SELECT id FROM htp_assessments WHERE child_id IN (SELECT id FROM k6_children));

-- htp_assessments 는 children 을 RESTRICT 로 잡는다(steps 는 위에서 이미 정리됨).
DELETE FROM htp_assessments WHERE child_id IN (SELECT id FROM k6_children);

-- reports → analyses 순서. 하위 report_* 테이블은 전부 CASCADE 다.
DELETE FROM reports WHERE id IN (SELECT id FROM k6_reports);
DELETE FROM analyses WHERE id IN (SELECT id FROM k6_analyses);

-- drawing_sessions 삭제로 stroke_batches·drawing_assets·conversation_sessions·
-- conversation_messages 등이 CASCADE 로 함께 사라진다.
DELETE FROM drawing_sessions WHERE id IN (SELECT id FROM k6_sessions);

-- consent_records 는 child·user 를 SET NULL 로 잡아 부모 삭제를 막지 않지만,
-- 합성 계정의 흔적을 남기지 않도록 명시적으로 지운다.
DELETE FROM consent_records WHERE subject_child_id IN (SELECT id FROM k6_children);

-- guardian_child_relations 는 CASCADE 라 children/users 삭제로 따라간다.
DELETE FROM children WHERE id IN (SELECT id FROM k6_children);
DELETE FROM users WHERE nickname = 'k6-load-guardian';

DROP TEMPORARY TABLE k6_analyses;
DROP TEMPORARY TABLE k6_reports;
DROP TEMPORARY TABLE k6_sessions;
DROP TEMPORARY TABLE k6_children;

COMMIT;

-- ── ③ 검증 (0 이어야 한다) ──────────────────────────────────────────────────
SELECT
    (SELECT COUNT(*) FROM children WHERE nickname LIKE 'k6-load-child-%') AS leftover_children,
    (SELECT COUNT(*) FROM users WHERE nickname = 'k6-load-guardian') AS leftover_guardian;
