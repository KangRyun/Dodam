-- 그림 활동 완료 접수에서 사용하는 최종 분석 작업 유형을 기존 분석 CHECK 계약에 추가한다.
-- 기존 OBJECT_DETECTION 행과 제약 이름은 유지해 운영 데이터 및 조회 코드와의 호환성을 보존한다.

ALTER TABLE analyses
    DROP CHECK ck_analyses_task_type,
    ADD CONSTRAINT ck_analyses_task_type CHECK (
        analysis_task_type IS NULL
        OR analysis_task_type IN ('OBJECT_DETECTION', 'ACTIVITY_REPORT'));
