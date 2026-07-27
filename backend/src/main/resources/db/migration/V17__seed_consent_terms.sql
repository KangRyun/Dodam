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
-- target_scope 결정 근거: 앱 온보딩은 consents/terms?targetScope=USER 만 조회·제출하므로
-- 가입 시점에 걸려야 하는 서비스 약관·마케팅만 USER, 아동 데이터에 관한 약관은 CHILD 로 둔다.
--
-- 필수 여부 결정(중요): USER-scope SERVICE_TOS 만 is_required=TRUE 로 둔다.
--   → 가입 온보딩은 USER-scope 필수 = SERVICE_TOS 동의를 요구하게 되어 vacuous-true 구멍이 닫힌다.
--   CHILD 약관은 앱 화면상 '필수'로 보이지만 여기서는 is_required=FALSE 로 시드한다. 이유:
--   대화 시작·음성 답변 authorization(ConversationStart/VoiceAnswerAuthorizationRepository)이
--   활성 필수 CHILD 약관에 아동 AGREE 이력이 있는지로 게이트한다. 그런데 아동 동의를 기록하는
--   흐름이 아직 없다(앱 아동 등록 요청에 consents 없음). CHILD 약관을 필수로 심으면 어떤 아동도
--   충족할 수 없어 대화가 영구 차단된다(2026-07-27 CI 실측: MvpFlow·Fallback 대화 테스트 실패).
--   → 아동 동의 기록 흐름이 생기면 그때 CHILD 약관을 TRUE 로 flip 한다.
--   같은 변경에서 위 두 authorization 쿼리에 target_scope='CHILD' 필터를 넣어, USER-scope
--   SERVICE_TOS 가 아동 게이트에 잘못 포함돼 대화를 막던 문제도 함께 고쳤다.
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
    ('CHILD_PERSONAL_INFO', 'CHILD', FALSE, 'v1', '아동 개인정보 수집·이용', '2020-01-01 00:00:00', TRUE),
    ('DRAWING_ANALYSIS',    'CHILD', FALSE, 'v1', '그림 데이터 분석 활용',   '2020-01-01 00:00:00', TRUE),
    ('VOICE_PROCESSING',    'CHILD', FALSE, 'v1', '음성 데이터 처리',        '2020-01-01 00:00:00', TRUE),
    ('EXPERT_SHARING',      'CHILD', FALSE, 'v1', '전문가 리포트 공유',      '2020-01-01 00:00:00', TRUE),
    ('AI_TRAINING',         'CHILD', FALSE, 'v1', 'AI 학습 데이터 활용',     '2020-01-01 00:00:00', TRUE),
    ('MARKETING',           'USER',  FALSE, 'v1', '마케팅 및 알림 수신',     '2020-01-01 00:00:00', TRUE);
