-- 온보딩 동의 약관(consent_terms) 기준 데이터를 시드한다.
--
-- 왜 필요한가(가드레일): ConsentRegistrationService.validateRequiredTerms 는 활성·필수 약관을
-- 모두 AGREE 했는지 stream().allMatch 로 검사한다. consent_terms 가 비어 있으면 필수 약관 집합이
-- 공집합이 되어 allMatch 가 vacuous-true 로 통과한다 → 아무 동의 없이 온보딩이 완료된다.
-- 아동 민감정보 서비스에서 "동의 없이 진입"은 타협 불가 위반(CLAUDE.md 9절)이라 필수 약관을
-- 실제로 심어 이 구멍을 막는다. 어떤 migration·시드에도 이 데이터가 없어 빈 테이블이었다(2026-07-27 실측).
--
-- 왜 마이그레이션인가: 수동 INSERT 는 컨테이너 재기동(fresh volume) 시 사라져 구멍이 재발한다.
-- 시드를 migration 으로 두면 fresh 배포·판정 환경에서도 항상 재현된다(V12 drawing_types·V15 폴백 질문과 동일 패턴).
--
-- scope·필수 결정 근거: 값은 임의로 정하지 않고 이미 배포된 앱과 게이팅 로직에서 역산했다.
--   - 필수 여부 = 앱 onboarding_consent_screen 의 isRequired 플래그 그대로
--     (SERVICE_TOS·아동개인정보·그림분석=필수, 음성·전문가공유·AI학습·마케팅=선택).
--   - target_scope: 앱 온보딩은 consents/terms?targetScope=USER 만 조회·제출하므로
--     가입 시점에 걸려야 하는 서비스 약관·마케팅만 USER, 아동 데이터에 관한 약관은 CHILD.
--     CHILD 약관은 childId 가 있어야 등록되므로(아동 등록 단계) 가입 온보딩을 막지 않는다.
--   → 결과적으로 가입 온보딩은 USER-scope 필수 = SERVICE_TOS 동의를 요구하게 된다.
--
-- content_html·content_url 을 NULL 로 두는 이유: 약관 원문(법무 확정 문구)이 확정되기 전이며,
-- V9 가 content_html 을 nullable 로 둔 것도 "원문 확정 전 구조만 시드" 를 허용하기 위함이다.
-- 구멍을 막는 데 필요한 것은 메타데이터(코드·범위·필수·활성)이고, 원문은 확정 후 UPDATE 한다.
--
-- effective_at 을 과거로 두는 이유: isEffectiveAt(now) 가 true 여야 활성 약관으로 조회된다.
-- version='v1' 은 초판을 뜻하며 uk_consent_terms_code_version(term_code, version) 로 재실행을 막는다.
--
-- 재실행 안전: (term_code, version) UNIQUE 자연 키가 있으므로 INSERT IGNORE 로 중복을 흡수한다
-- (이미 심긴 뒤 다시 돌아도 무해). V12 와 동일 방식.

INSERT IGNORE INTO consent_terms (
    term_code,
    target_scope,
    is_required,
    version,
    title,
    effective_at,
    is_active
) VALUES
    ('SERVICE_TOS',         'USER',  TRUE,  'v1', '서비스 이용약관',        '2020-01-01 00:00:00', TRUE),
    ('CHILD_PERSONAL_INFO', 'CHILD', TRUE,  'v1', '아동 개인정보 수집·이용', '2020-01-01 00:00:00', TRUE),
    ('DRAWING_ANALYSIS',    'CHILD', TRUE,  'v1', '그림 데이터 분석 활용',   '2020-01-01 00:00:00', TRUE),
    ('VOICE_PROCESSING',    'CHILD', FALSE, 'v1', '음성 데이터 처리',        '2020-01-01 00:00:00', TRUE),
    ('EXPERT_SHARING',      'CHILD', FALSE, 'v1', '전문가 리포트 공유',      '2020-01-01 00:00:00', TRUE),
    ('AI_TRAINING',         'CHILD', FALSE, 'v1', 'AI 학습 데이터 활용',     '2020-01-01 00:00:00', TRUE),
    ('MARKETING',           'USER',  FALSE, 'v1', '마케팅 및 알림 수신',     '2020-01-01 00:00:00', TRUE);
