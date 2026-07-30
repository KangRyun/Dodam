#!/usr/bin/env node
// ============================================================================
// 합성 계정용 Access Token 오프라인 발급 (S15P11B209-354)
//
// 왜 로그인 API 를 안 쓰나: 소셜 로그인은 카카오·네이버·구글을 실제로 호출한다.
//   부하 테스트 준비 단계에서 남의 IdP 를 때릴 이유가 없고, 합성 계정에는
//   애초에 소셜 계정이 없다. 백엔드가 검증하는 것은 서명·발급자·만료·용도뿐이라
//   같은 Secret 으로 우리가 직접 서명하면 그대로 통과한다.
//
//   백엔드 계약 (JwtTokenIssuer / JwtAccessTokenDecoder):
//     alg=HS256 · iss=JWT_ISSUER · sub=<userId> · token_type="access" · exp · iat · jti
//
// ⚠️ 반드시 **서버에서** 실행한다. JWT_SECRET 은 서버 밖으로 나가면 안 된다.
//    출력된 토큰은 그 자체가 자격증명이다 — 커밋·공유·로그 기록 금지.
//    합성 계정 외의 userId 로는 절대 발급하지 않는다.
//
// 사용:
//   JWT_SECRET=... node tools/issue-token.mjs --user-id 1001 --ttl-minutes 120
//   (또는 서버에서) kubectl -n dodam exec deploy/backend -- printenv JWT_SECRET  ← 값 노출 주의
// ============================================================================
import { createHmac, randomUUID } from 'node:crypto';

const args = parseArgs(process.argv.slice(2));

const secret = process.env.JWT_SECRET || args['secret'];
const issuer = process.env.JWT_ISSUER || args['issuer'] || 'dodam-api';
const userId = args['user-id'];
const ttlMinutes = Number(args['ttl-minutes'] || 120);

if (!secret) {
  fail('JWT_SECRET 이 없습니다. 서버에서 환경변수로 넘기세요 (인자로 넘기면 셸 히스토리에 남습니다).');
}
if (Buffer.byteLength(secret, 'utf8') < 32) {
  fail('JWT_SECRET 이 32바이트 미만입니다 — 백엔드가 AUTH_CONFIGURATION_INVALID 로 거부합니다.');
}
if (!userId || !/^\d+$/.test(String(userId))) {
  fail('--user-id 에 합성 보호자의 숫자 ID 를 주세요. (sql/seed.sql 출력 참고)');
}
if (!Number.isFinite(ttlMinutes) || ttlMinutes <= 0 || ttlMinutes > 720) {
  fail('--ttl-minutes 는 1~720 사이여야 합니다.');
}

const now = Math.floor(Date.now() / 1000);
const token = sign(
  { alg: 'HS256', typ: 'JWT' },
  {
    iss: issuer,
    sub: String(userId),
    iat: now,
    exp: now + ttlMinutes * 60,
    jti: randomUUID(),
    token_type: 'access',
  },
  secret,
);

// 토큰만 stdout 으로 — 파이프로 바로 받을 수 있게. 안내는 stderr 로 분리한다.
process.stderr.write(
  `발급 완료: userId=${userId} issuer=${issuer} 만료=${ttlMinutes}분\n` +
    '⚠️ 이 값은 자격증명입니다. 파일로 저장하면 chmod 600, 테스트 후 삭제하세요.\n',
);
process.stdout.write(`${token}\n`);

function sign(header, payload, key) {
  const encode = (object) => Buffer.from(JSON.stringify(object)).toString('base64url');
  const signingInput = `${encode(header)}.${encode(payload)}`;
  const signature = createHmac('sha256', Buffer.from(key, 'utf8')).update(signingInput).digest('base64url');
  return `${signingInput}.${signature}`;
}

function parseArgs(argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith('--')) continue;
    const name = argv[i].slice(2);
    const next = argv[i + 1];
    parsed[name] = next && !next.startsWith('--') ? (i += 1, next) : 'true';
  }
  return parsed;
}

function fail(message) {
  process.stderr.write(`[issue-token] ${message}\n`);
  process.exit(2);
}
