# 도담 CI/CD 가이드 (Jenkins)

> 관련 이슈: S15P11B209-189, S15P11B209-1021 · 최종 갱신: 2026-08-09
>
> **한 줄 요약: 변경된 영역만 테스트·빌드하고, develop에서는 변경된 서버 이미지만 배포합니다.**

---

## 1. 전체 흐름

```
push/머지 (GitLab)
   │  ← Jenkins가 2분 주기 폴링으로 감지
   ▼
[모든 브랜치]  Checkout → 변경 범위 판정
              → Backend 변경: 작업 브랜치·develop quickTest / MR 전체 test
              → Flutter 변경: Flutter test
   │
   ▼  (develop 브랜치만 계속 진행)
[develop 전용] 변경 서비스만 Docker Build(+SHA 태그)
              → 변경 서비스만 레지스트리 push·배포
              → Healthcheck (실행 서비스 상태 + 공개 경로 e2e)
```

- **테스트 실패 = 그 자리에서 중단.** develop이면 배포되지 않습니다(운영 보호 게이트).
- 작업 브랜치와 `develop`은 Testcontainers 통합 테스트를 제외한 `quickTest`, MR은 전체 `test`를 실행합니다.
- 릴리스 전이나 대규모 변경은 Jenkins의 `FORCE_FULL_TESTS=true`로 어떤 브랜치에서도 전체 테스트를 강제할 수 있습니다.
- Gradle Daemon·Build Cache와 Flutter의 job별 named volume을 재사용합니다. 반복 빌드 전에 `clean`으로 캐시를 지우지 않습니다.
- 문서나 모바일만 바뀐 develop 빌드는 서버 이미지 빌드·배포·Healthcheck를 건너뜁니다.
- `Jenkinsfile`이나 서비스 경계를 특정하기 어려운 `infra/**` 변경은 안전하게 전체 서버 빌드로 폴백합니다.
- 같은 SHA 재배포나 변경 감지 복구가 필요하면 Jenkins의 `FORCE_SERVER_REBUILD`를 켜 전체 파이프라인을 강제합니다.

## 2. 팀원이 알아야 할 것 3가지

1. **develop 머지 후 서버 변경이 있으면 배포**됩니다. 머지 전 MR 브랜치 빌드가 초록인지 확인하세요.
2. **MR 브랜치에 develop을 자주 머지**하세요. 파이프라인(Jenkinsfile)은 *각 브랜치에 있는 버전*으로 실행되므로, develop을 머지해야 최신 파이프라인·알림이 적용됩니다.
3. **Mattermost 알림 읽는 법:**

   > ❌ **빌드 실패** · `feature/xxx` #4 · 1 min 26 sec
   > 👤 홍길동 · 커밋 `782908e1`
   > 💥 실패 지점: Build & Test — backend
   > 🧪 실패 테스트 22건: SwaggerEndpointTest, DrawingSessionIntegrationTest, ...

   - `👤` = 그 브랜치 마지막 커밋 작성자 · `💥` = 실패한 스테이지 · `🧪` = 실패 테스트 클래스(테스트 실패일 때만)
   - ✅ 알림에 `🚀 서버 배포됨`이 붙으면 develop이 실서버에 반영된 것입니다.
   - `⏭️ 서버 변경 없음(배포 생략)`은 모바일·문서 변경처럼 서버 배포가 필요 없었다는 뜻입니다.

## 3. 빌드 상세 확인 (Jenkins 접속)

Jenkins는 보안상 **외부에 노출돼 있지 않습니다**(서버 내부 127.0.0.1:9090만). 접속은 SSH 터널로:

```bash
ssh -L 9090:localhost:9090 <본인계정>@i15b209.p.ssafy.io
# 터널 유지한 채 브라우저에서
http://localhost:9090   → dodam-cicd 잡 → 브랜치 → Console Output / Test Result
```

## 4. 구성 요소 (Infra 참고)

| 항목 | 내용 |
|---|---|
| 파이프라인 정의 | 저장소 루트 `Jenkinsfile` (Multibranch — 브랜치별 자동 감지) |
| Jenkins 본체 | 이 EC2의 컨테이너 `dodam-jenkins` (`infra/jenkins/` — 커스텀 이미지 + compose) |
| 빌드/배포 방식 | 호스트 docker.sock 사용, **레지스트리 없이 로컬 빌드** 후 같은 데몬에서 `compose up` |
| 이미지 태그 | `:local`(배포용) + `:{짧은SHA}`(빌드마다 남는 불변 복원지점 — 롤백용, S15P11B209-190) |
| 트리거 | **SCM 폴링 2분** — 웹훅 대신 선택(Jenkins 외부 미노출 보안 결정). HTTPS(S15P11B209-301) 적용 후 웹훅 업그레이드 검토 |
| Credentials (Jenkins 금고) | `gitlab-token`(레포 읽기) · `dodam-env`(배포용 .env) · `mattermost-webhook`(알림) — **값은 Jenkins UI에서만, 저장소·채팅 공유 금지** |
| 변경 범위 판정 | `infra/scripts/ci-change-scope.sh` — 판정 불가 시 전체 검증으로 폴백 |
| CI 정책 회귀 테스트 | `infra/scripts/ci-build-policy-test.sh` |

## 5. 자주 있는 상황 대응

> 배포 후 검증 절차·장애 판단·롤백은 **[배포검증-롤백.md](배포검증-롤백.md)** (S15P11B209-190) 참조 — 새벽 장애 대응 runbook.

| 상황 | 대응 |
|---|---|
| ❌ 알림 받음 (내 브랜치) | `💥 지점`·`🧪 테스트` 확인 → 수정 후 다시 push (자동 재빌드) |
| develop 빌드 실패 | **배포 안 됨 — 운영은 직전 정상 버전 유지.** 원인 커밋 작성자가 수정 MR → 머지되면 자동 복구 |
| Healthcheck 실패 | 배포됐지만 컨테이너가 unhealthy — Infra(이강륜) 호출. `docker logs <컨테이너>`로 원인 확인 |
| Jenkins 자체 재시작 필요 | (Infra) `docker compose -f infra/jenkins/docker-compose.yml restart` — 설정·잡·크레덴셜은 볼륨(jenkins-home)에 보존 |

## 6. 이력

- **2026-08-09** 빌드 최적화(S15P11B209-1021): 변경 범위 기반 테스트·이미지 빌드·배포, 작업 브랜치 `quickTest`, Gradle/Flutter 증분 캐시 적용.
- **2026-07-22** 최초 구축(S15P11B209-189): Jenkins 컨테이너 + Multibranch 파이프라인 + 폴링 + MM 알림.
  브랜치=테스트만/develop=풀파이프라인 게이팅. 첫 주 성과: 부팅 크래시 버그 2건(배포 전 차단 1건 포함) 조기 발견.
