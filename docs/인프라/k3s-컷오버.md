# k3s 프로덕션 컷오버 runbook (S15P11B209-360)

> 대상: EC2 `i15b209.p.ssafy.io` · 담당: Infra(이강륜)
> 목표 순단: **10분 이내** · 저녁 공지 창
> 선행: 357(매니페스트) ✅ · 358(스테이징) ✅ · 359(파이프라인 kubectl) ✅ · 361(모니터링) ✅ · 362(무중단 실증) ✅

⚠️ **이 문서의 명령은 운영 서비스를 멈춘다. 제안이지 실행이 아니다.**
⚠️ **이 작업은 아동 데이터(MySQL·MinIO)를 옮긴다.** 백업 없이 시작하지 않는다. 가드레일 9절.

> 🗄️ **이 문서는 2026-07-29 에 끝난 작업의 기록이다 — 지금 따라 하는 절차가 아니다.**
> 특히 여기 적힌 **compose 원복 경로(`docker compose … up -d`)는 더 이상 존재하지 않는다.**
> `infra/docker-compose.yml` 은 S15P11B209-791 에서 빌드 전용 `infra/docker-compose.build.yml` 로
> 축소됐고, 실행 정의(mysql·minio·nginx…)가 없다. 실행해도 스택이 뜨지 않으며, 억지로 되살리면
> k8s gateway 와 hostPort 를 다투거나 빈 도커 볼륨을 물고 올라온다.
> **현재의 배포·롤백 절차는 `배포검증-롤백.md` §2 다.**

---

## 0. 이건 "설정 전환"이 아니다

다른 이슈들과 성격이 다르다. 359·361·362 는 실패해도 운영이 살아 있었다. 이건 **운영을
멈추고 데이터를 옮긴다.** 되돌리는 비용이 처음으로 비싸진다.

그래서 이 문서의 절반은 **롤백**이다. 5분 안에 원복하지 못하면 시작하지 않는다.

---

## 1. 시작 전 관문 (하나라도 ❌ 면 연기)

| # | 확인할 것 | 명령 | 통과 기준 |
| --- | --- | --- | --- |
| 1 | 최신 백업 존재 | `ls -lt /var/backups/dodam \| head -3` | 오늘 자 파일 |
| 2 | 메모리 여유 | `infra/scripts/preflight-memory.sh --need 4096` | 종료코드 0 |
| 3 | k3s 정상 | `kubectl get node` | `Ready` |
| 4 | Secret 동기화 | `kubectl -n dodam get secret dodam-secrets` | 존재 |
| 5 | **`:prod` 태그 이미지** | `curl -s 127.0.0.1:5000/v2/dodam-backend/tags/list` | `prod` 포함 |
| 6 | Jenkins 배포 프리즈 | `docker exec dodam-jenkins ls /var/jenkins_home/DEPLOY_FREEZE` | 존재 |
| 7 | UFW 규칙 | runbook 7단계 참조 | 6443 허용 |
| 8 | 팀 공지 | Mattermost | 창 시작 15분 전 |

### 5번이 지금 비어 있다

prod overlay 는 `127.0.0.1:5000/dodam-{backend,ai,nginx}:prod` 를 참조하는데, 레지스트리에는
`staging` 과 커밋 SHA 태그만 있다. **ai 는 아직 한 번도 push 된 적이 없다**(2.36GB).

```bash
# 컷오버 당일 낮에 미리 해 둘 것 — 창 안에서 2.36GB 를 밀면 순단이 길어진다
infra/scripts/push-staging-images.sh --tag prod --with-ai
```

---

## 2. 옮길 것 (2026-07-29 실측)

| 볼륨 | 크기 | 내용 | 이관 |
| --- | --- | --- | --- |
| `dodam_mysql-data` | **253.4M** | **아동·보호자 데이터** | dump → restore |
| `dodam_minio-data` | **7.2M** | **아동 그림·음성** | 볼륨 복사 |
| `dodam_backend-storage` | 492K | 그림 로컬 저장분 | 볼륨 복사 |
| `dodam_letsencrypt` | 100K | TLS 인증서 | **tar** (심링크) |
| `dodam_ai-models` | 36.8M | YOLO 가중치 | 볼륨 복사 |
| `dodam_apk-dist` · `certbot-webroot` | 4K | 배포 산출물·ACME | 복사 |
| `dodam_redis-data` | 812K | 캐시 | **옮기지 않는다**(재생성 가능) |
| `dodam_mongo-data` | 4K | 비어 있음 | 해당 없음 |

> ⚠️ **`letsencrypt` 는 반드시 `tar` 로 옮긴다.** `live/*.pem` 이 `archive/` 로 향하는 심링크다.
> `cp -r` 는 심링크를 따라가 실체를 복사해 버리고, 갱신 시 경로가 어긋난다.
> (2026-07-29 인증서 이관에서 실제로 걸렸던 지점)

---

## 3. 절차

### T-15분 — 공지·동결

```bash
# Mattermost 공지 (수동)
#   "23:00~23:15 서버 점검 — 도담 앱·웹 일시 중단됩니다"

docker exec dodam-jenkins sh -c 'echo "360 컷오버 진행 중 — 강륜" > /var/jenkins_home/DEPLOY_FREEZE'
infra/scripts/k3s-baseline.sh capture before   # 되돌릴 기준선
```

### T0 — 최종 백업 (순단 시작 전, 서비스는 아직 살아 있다)

```bash
infra/scripts/mysql-backup.sh
infra/scripts/minio-backup.sh
ls -lt /var/backups/dodam | head -3      # 방금 것이 맨 위인지 눈으로 확인
```

### T+1 — 앱 정지 (여기서 순단 시작)

```bash
# ⚠️ nginx 를 **먼저** 내린다. hostPort 80/443 을 쥐고 있으면 gateway 파드가 뜨지 못한다
#    (prod overlay 는 hostPort 방식 — servicelb 를 껐기 때문이다)
docker compose -f infra/docker-compose.yml stop nginx backend ai
```

### T+2 — 데이터 이관

```bash
# ── MySQL: dump → k8s 파드로 복원
docker exec dodam-mysql mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
  --single-transaction --routines --triggers dodam > /tmp/cutover.sql

kubectl -n dodam exec -i mysql-0 -- \
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" dodam < /tmp/cutover.sql

# ── 파일 볼륨: tar 스트리밍 (심링크 보존)
for v in minio-data backend-storage letsencrypt ai-models apk-dist certbot-webroot; do
  docker run --rm -v "dodam_${v}":/src alpine tar -C /src -cf - . \
    | kubectl -n dodam exec -i <해당파드> -- tar -C <마운트경로> -xf -
done
```

> `<해당파드>`·`<마운트경로>` 는 실행 시점에 `kubectl -n dodam get pods` 로 확인해 채운다.
> 자리표시자를 그대로 붙여넣지 말 것.

### T+5 — row count 대조 (★ 이관 성공 판정)

```bash
# 같은 쿼리를 양쪽에 돌려 숫자가 같은지 본다. "옮겼다"와 "다 옮겨졌다"는 다르다.
Q="SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='dodam' ORDER BY table_name"
docker exec dodam-mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "$Q" > /tmp/before.txt
kubectl -n dodam exec mysql-0 -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "$Q" > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt && echo "✅ 일치"
```

> `information_schema.table_rows` 는 InnoDB 에서 **근사값**이다. 핵심 테이블
> (`users`·`children`·`drawing_sessions`·`conversation_messages`)은 `COUNT(*)` 로 따로 센다.

### T+7 — k3s 기동

```bash
kubectl apply -k infra/k8s/overlays/prod
kubectl -n dodam rollout status deployment/backend --timeout=300s
kubectl -n dodam rollout status deployment/gateway --timeout=300s
kubectl -n dodam get pods
```

### T+9 — e2e 확인

```bash
for u in / /ai/health /api/v1/children /legal/privacy/; do
  printf "%-22s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' -m 8 "https://i15b209.p.ssafy.io$u")"
done
# 기대: 200 · 200 · 401 · 200
```

**이 4줄이 기준선과 같아야 컷오버 성공이다.** 파드가 Running 인 것으로 판단하지 않는다.

### T+10 — compose DB 정지 · Jenkins 전환

```bash
docker compose -f infra/docker-compose.yml stop mysql redis minio
# Jenkins Deploy 스테이지를 kubectl 로 전환 (359 의 스테이징 스테이지를 운영 경로로 승격)
docker exec dodam-jenkins rm /var/jenkins_home/DEPLOY_FREEZE
```

---

## 4. 롤백 — 5분 안에 원복

**판단 기준: T+9 e2e 가 2회 연속 실패하면 되돌린다.** 원인 분석은 원복 후에 한다.

```bash
kubectl -n dodam scale deployment/gateway --replicas=0   # hostPort 80/443 을 놓는다
docker compose -f infra/docker-compose.yml up -d          # 5분 원복
```

- compose 자산(컨테이너·볼륨)은 **컷오버 후 1주일 무접촉 보존**한다. 지우지 않는다
- MySQL 은 컷오버 중 k8s 쪽에만 썼으므로, 원복 시 그 사이 데이터는 **유실된다**.
  순단 창 안이라 사용자 트래픽이 없다는 전제다 — 창을 넘기면 이 전제가 깨진다

---

## 5. 관찰 창 (15분)

```bash
kubectl -n dodam get events --sort-by=.lastTimestamp | tail -20
kubectl -n dodam top pod
kubectl -n dodam port-forward svc/prometheus 19090:9090   # 별도 창
```

- Grafana `/grafana/` 가 이제 k3s 판을 가리킨다(361 에서 Service `dodam-grafana` 생성 완료)
- 경보 규칙이 k8s 라벨 기준으로 다시 쓰여 있다 — `ContainerMemoryNearLimit` 이 실제로 시계열을 잡는지 확인

---

## 6. 컷오버 후 정리

- [ ] compose 모니터링 폐기 (`infra/monitoring/docker-compose.yml down`) — 361 의 마지막 작업
- [ ] certbot CronJob `renew --dry-run` 검증
- [ ] 운영에서 롤링 무중단 재확인 (362 는 스테이징 실증이었다)
- [ ] 1주 뒤 compose 자산 정리

---

## 7. 함정 모음 (2026-07-29 실측)

이날 359·361·362 를 하면서 실제로 밟은 것들이다. 컷오버에서 재발할 수 있다.

| 함정 | 증상 | 대응 |
| --- | --- | --- |
| **hostPort 충돌** | gateway 파드가 Pending/CrashLoop | compose nginx 를 **먼저** stop |
| **`:prod` 태그 부재** | ImagePullBackOff | 당일 낮에 `--tag prod --with-ai` 로 미리 push |
| **UFW** | Jenkins→API `i/o timeout`(연결 거부 아님) | 6443 허용 규칙. **서버 재구축 시 사라진다** |
| **Jenkins 이미지 미재빌드** | `kubectl: not found` | Dockerfile 수정만으로는 안 된다. 이미지 재빌드 필요 |
| **NodePort 로 검증** | k3s 가 죽어도 200 이 나온다 | 공개 도메인으로 e2e. 스테이징은 클러스터 안에서 |
| **심링크** | 인증서 갱신이 깨진다 | `cp -r` 금지, `tar` 사용 |
| **preStop 부재** | 롤링 중 요청이 60초 매달림 | 이미 반영됨(362) |
| **rollout status 만 믿기** | replicas 0 이면 즉시 성공한다 | `readyReplicas >= 1` 을 따로 본다 |
| **경보 규칙 라벨** | 규칙은 있는데 영원히 안 울린다 | k8s 라벨(`pod`·`container`)로 재작성 — 361 에서 완료 |

---

## 참조

- `docs/인프라/k3s-설치-runbook.md` — 설치·스테이징·파이프라인 전환(7단계)
- `docs/성능/2026-07-29-롤링-무중단-실증.md` — preStop 근거
- `docs/인프라/메모리-OOM-대응.md` — 메모리 방어 체계
- 매니페스트: `infra/k8s/overlays/prod/`
