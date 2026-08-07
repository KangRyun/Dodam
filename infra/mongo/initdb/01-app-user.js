// 앱 전용 최소권한 계정 생성 (S15P11B209-364)
//
// 값은 컨테이너 환경변수로 들어온다 — 이 파일에 비밀은 없다.
// entrypoint 가 mongosh 로 실행하므로 process.env 로 읽는다.
const dbName   = process.env.MONGO_INITDB_DATABASE;
const appUser  = process.env.MONGO_APP_USERNAME;
const appPass  = process.env.MONGO_APP_PASSWORD;

if (!dbName || !appUser || !appPass) {
  // fail-fast — 계정 없이 떠 버리면 앱이 붙는 시점에야 알게 된다.
  //   compose 의 `:?` 가드와 같은 취지: 조용한 반쪽 성공을 만들지 않는다.
  throw new Error(
    'MONGO_INITDB_DATABASE / MONGO_APP_USERNAME / MONGO_APP_PASSWORD 가 필요하다. ' +
    'infra/scripts/sync-secrets.sh 로 dodam-secrets 에 넣었는지 확인할 것.'
  );
}

db = db.getSiblingDB(dbName);
db.createUser({
  user: appUser,
  pwd:  appPass,
  // readWrite 만 준다. dbAdmin(인덱스 생성·삭제)은 주지 않는다 —
  //   인덱스는 이 초기화 스크립트와 634 의 관리 절차에서만 다룬다.
  //   앱이 임의로 인덱스를 만들면 TTL 정책이 코드 곳곳으로 흩어진다.
  roles: [{ role: 'readWrite', db: dbName }],
});

print(`✅ 앱 계정 생성: ${appUser} (readWrite on ${dbName})`);
