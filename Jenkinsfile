// 도담 CI/CD 파이프라인 — 단일 EC2 · 레지스트리 없이 로컬 빌드 · develop 배포
// 관련 이슈: S15P11B209-189 (Jenkins CI/CD)
//
// 잡 유형: Multibranch Pipeline 권장(브랜치 자동 감지 → env.BRANCH_NAME 세팅). Deploy는 develop에서만.
// 전제:
//   - Jenkins 컨트롤러에 docker CLI + compose 플러그인 + 호스트 docker.sock (infra/jenkins/ 이미지)
//   - 시크릿 .env 는 Jenkins Credentials(secret file)로 주입 — 저장소 커밋 금지
//       · dodam-env         : 이미지 **빌드** 인자 (infra/docker-compose.build.yml)
//       · dodam-env-compose : compose **실행** 정의용 (infra/docker-compose.yml) ← 컷백에서 신설
//       · dodam-kubeconfig  : k3s 배포용(네임스페이스 한정 ServiceAccount)
//   - 컨트롤러 인-빌드(별도 에이전트 없음)
//
// 흐름: Checkout → [develop만] Secrets Preflight → Build&Test(backend) → [이하 develop만] Docker Build → ai import 스모크 → Deploy → Healthcheck
//   브랜치(MR) 빌드는 테스트까지만 — 자원 절약 + 모든 브랜치가 :local 태그를 덮어쓰는 레이스 방지.
// 알림: 빌드 성공/실패를 Mattermost Incoming Webhook으로 전송 (크레덴셜 id: mattermost-webhook)
//
// ★★ 배포 대상 스위치 (DEPLOY_TARGET) — 2026-08-07 컷백 대응 ★★
//   발표 대비로 운영을 k3s → docker-compose 로 **되돌린다**(컷백). 그런데 이 파이프라인의
//   Deploy 는 `kubectl set image` 였으므로, k3s 를 내리는 순간 배포가 통째로 깨진다.
//   그래서 **두 경로를 다 남기고 스위치로 고른다.** k3s 경로를 지우지 않은 이유는 하나다:
//   컷백이 실패해 되돌아갈 때 "파이프라인까지 다시 고치는" 상황을 만들지 않기 위해서다.
//
//   고르는 방법(우선순위):
//     ① 빌드 파라미터 DEPLOY_TARGET = compose | k3s   (일회성 강제)
//     ② auto(기본) → 파일 /var/jenkins_home/DEPLOY_TARGET 의 내용
//     ③ 파일도 없으면 **compose**  ← 컷백 기간 fail-safe (2026-08-08 k3s→compose 로 변경)
//   ⚠️ 기본값을 k3s→compose 로 뒤집었다. 컷백 기간엔 스위치 파일이 유실돼도 죽은 k3s 가 아니라
//     현재 현실(compose)로 안전하게 떨어져야 한다. (직전엔 기본이 k3s 라 파일이 없으면 kubectl 로
//     죽은 클러스터에 배포 시도 → 실패했다 — 이 변경의 이유.) 여전히 파일이 실질 스위치다:
//       compose 유지: docker exec dodam-jenkins sh -c 'echo compose > /var/jenkins_home/DEPLOY_TARGET'
//       k3s 롤백:     docker exec dodam-jenkins sh -c 'echo k3s > /var/jenkins_home/DEPLOY_TARGET'
//     (런타임에 읽으므로 즉시 적용·재시작해도 유지. ★ k3s 로 완전 롤백 시 이 기본값도 k3s 로 되돌릴지 검토)

// 실패 알림에 붙일 "어디서 터졌나" 분석 — 실패 스테이지 + (테스트 실패면) 실패 테스트 요약.
//   분석이 실패해도 알림 자체는 나가야 하므로 try/catch로 감싼다.
def failureDetail() {
  def detail = "\n💥 실패 지점: ${env.CURRENT_STAGE ?: '?'}"
  try {
    // 테스트 스테이지에서 죽었을 때만 junit XML 분석
    // (다른 스테이지 실패 시 이전 빌드의 잔재 결과를 잘못 읽는 것 방지)
    if ((env.CURRENT_STAGE ?: '').contains('backend')) {
      def cnt = sh(returnStdout: true,
        script: 'grep -h "<failure" backend/build/test-results/test/*.xml 2>/dev/null | wc -l').trim()
      if (cnt && cnt != '0') {
        // 실패 포함 클래스명(패키지 제거) 상위 5개를 콤마로
        def classes = sh(returnStdout: true,
          script: 'grep -l "<failure" backend/build/test-results/test/*.xml 2>/dev/null | sed -e "s/.*TEST-//" -e "s/\\.xml//" -e "s/.*\\.//" | head -5 | paste -sd ", " -').trim()
        detail += "\n🧪 실패 테스트 ${cnt}건: ${classes}"
      }
    }
  } catch (ignored) { }   // 분석 실패는 조용히 무시 — 알림은 계속
  return detail
}

// Mattermost 알림 — 알림 실패가 빌드 결과를 바꾸면 안 되므로 try/catch + `|| true`로 이중 방어.
//   크레덴셜(mattermost-webhook, Secret text)이 아직 없으면 경고만 찍고 넘어간다.
def notifyMattermost(String emoji, String title) {
  try {
    withCredentials([string(credentialsId: 'mattermost-webhook', variable: 'MM_WEBHOOK')]) {
      def branch   = env.BRANCH_NAME ?: '?'
      def duration = (currentBuild.durationString ?: '').replace(' and counting', '')
      // 프리즈 중에는 "배포됨"이라고 쓰면 안 된다 — 알림만 보고 배포된 줄 아는 게 가장 위험하다.
      def deployed = ''
      if (branch == 'develop' && emoji == '✅') {
        // 컷백 기간에는 "어디에 배포됐는가"가 배포 여부만큼 중요하다 — 알림에 대상을 함께 적는다.
        deployed = (env.DEPLOY_FROZEN == 'true')
          ? ' · ⏸️ 배포 프리즈(미배포)'
          : " · 🚀 서버 배포됨(${env.DEPLOY_TARGET ?: '?'})"
      }
      // 빌드 링크 — Jenkins가 https://…/jenkins/ 로 공개(S15P11B209-319)되며 클릭 가능해짐.
      //   BUILD_URL은 Manage Jenkins의 "Jenkins URL" 설정 기반으로 생성됨(로그인 필요).
      def link = env.BUILD_URL ? " · [빌드 보기](${env.BUILD_URL})" : ''
      def text = "${emoji} **${title}** · `${branch}` #${env.BUILD_NUMBER} · ${duration}${deployed}\n" +
                 "👤 ${env.GIT_AUTHOR ?: '?'} · 커밋 `${env.IMAGE_TAG ?: '?'}`${link}"
      if (emoji == '❌') { text += failureDetail() }   // 실패면 "어디서 터졌나" 분석 첨부
      // JSON은 이스케이프 사고 방지를 위해 파일로 만들어 curl -d @file 로 전송(따옴표 지옥 회피)
      writeFile file: '.mm-payload.json', text: groovy.json.JsonOutput.toJson([text: text])
      sh 'curl -sf -X POST -H "Content-Type: application/json" -d @.mm-payload.json "$MM_WEBHOOK" || true'
    }
  } catch (err) {
    echo "Mattermost 알림 전송 실패(빌드에는 영향 없음): ${err}"
  }
}

pipeline {
  agent any

  options {
    timestamps()                       // 로그에 시각 표기
    disableConcurrentBuilds()          // 동일 파이프라인 동시 실행 금지(배포 충돌 예방)
    // 30분 → 60분 (S15P11B209-623): AAB 스테이지는 gradle 캐시가 빈 첫 회에 10~20분이 든다.
    //   백엔드 테스트(약 10분)와 합치면 30분을 넘겨 "타임아웃으로 죽었는데 원인은 안 보이는" 빌드가 된다.
    //   AAB 를 요청하지 않은 빌드는 예전과 똑같이 끝나므로 실질 영향은 없다.
    timeout(time: 60, unit: 'MINUTES') // 무한 매달림 방지
  }

  parameters {
    // 기본 false — 매 푸시마다 AAB 를 굽는 건 낭비다(수 분 + 디스크). 필요할 때만 켜서 돌린다.
    // ※ Multibranch 잡은 이 블록을 **한 번 실행한 뒤에야** 파라미터를 인식한다.
    //    이 커밋 후 첫 빌드에는 체크박스가 안 보이는 게 정상이고, 그 다음 빌드부터 나온다.
    booleanParam(
      name: 'BUILD_ANDROID_AAB',
      defaultValue: false,
      description: 'Android 릴리스 AAB 를 빌드한다 (Jenkins Credentials 3종 필요 — S15P11B209-623)'
    )
    // 앱 테스트는 기본적으로 frontend/mobile 변경 시에만 돈다. 이 값을 켜면 변경과 무관하게 실행한다
    //   (빌더 이미지 재빌드 후 회귀 확인 등 — S15P11B209-642).
    booleanParam(
      name: 'FORCE_APP_TESTS',
      defaultValue: false,
      description: 'frontend/mobile 변경이 없어도 Flutter 앱 테스트를 실행한다 (S15P11B209-642)'
    )
    // ※ DEPLOY_K8S_STAGING(359)은 제거했다. 컷오버(360) 후 운영 배포 자체가 k3s 로 가므로
    //   "스테이징에만 따로 배포"라는 개념이 사라졌다 — 같은 네임스페이스를 두 번 배포하게 된다.

    // 배포 대상 스위치(컷백). 기본 auto = JENKINS_HOME/DEPLOY_TARGET 파일 값, 없으면 compose(2026-08-08 변경).
    //   파라미터 인식 지연(위 주석) 때문에 **파일이 실질 스위치**다 — 파일 헤더 설명 참조.
    choice(
      name: 'DEPLOY_TARGET',
      choices: ['auto', 'compose', 'k3s'],
      description: '배포 대상. auto = /var/jenkins_home/DEPLOY_TARGET 파일 값(없으면 compose)'
    )
    // compose 는 **이미지 참조가 바뀔 때만** 컨테이너를 재생성한다. 같은 SHA 를 다시 배포하면
    //   재생성이 일어나지 않아 옛 컨테이너가 그대로 남는다. Healthcheck 의 다이제스트 대조가
    //   그걸 잡아 빌드를 실패시키므로, 그때 이 값을 켜서 다시 돌린다.
    //   기본 false 인 이유: 매 배포에 강제 재생성을 걸면 불필요한 순단이 늘어난다.
    booleanParam(
      name: 'COMPOSE_FORCE_RECREATE',
      defaultValue: false,
      description: 'compose 배포 시 --force-recreate 를 붙인다 (같은 SHA 재배포용)'
    )
  }

  environment {
    // 이미지 빌드 전용 compose. 실행 정의는 들어 있지 않다(S15P11B209-791) — 운영은 k3s 소관.
    // (Jenkins 자체 compose `infra/jenkins/docker-compose.yml` 와 다른 파일이다)
    COMPOSE_FILE = 'infra/docker-compose.build.yml'
    // ★ 컷백 실행 정의(8서비스). 이미지를 굽는 파일과 **역할이 다르다**:
    //     이미지 굽기 → COMPOSE_FILE(build.yml) · 서비스 실행 → 이 파일
    //   이 파일은 시크릿을 `${VAR:?}` 로만 참조하므로 dodam-env-compose 크레덴셜과 짝이다.
    COMPOSE_RUN_FILE = 'infra/docker-compose.yml'
    // 배포 대상 스위치 파일(파라미터 인식 지연 회피 — 파일 헤더 ★★ 절 참조).
    DEPLOY_TARGET_FLAG = '/var/jenkins_home/DEPLOY_TARGET'
    // 배포 프리즈 플래그 — 이 파일이 있으면 develop 빌드도 배포하지 않는다(S15P11B209-358).
    //   왜 파라미터가 아니라 파일인가: Multibranch 는 새 파라미터를 "한 번 돌린 뒤"에야 인식한다
    //   (위 parameters 주석 참조). 정작 막아야 할 다음 빌드에 안 먹으므로 프리즈 용도로는 못 쓴다.
    //   파일은 런타임에 읽으므로 즉시 적용된다. JENKINS_HOME 은 영속 볼륨이라 재시작해도 남는다.
    //   설정: docker exec dodam-jenkins touch /var/jenkins_home/DEPLOY_FREEZE
    //   해제: docker exec dodam-jenkins rm  /var/jenkins_home/DEPLOY_FREEZE
    DEPLOY_FREEZE_FLAG = '/var/jenkins_home/DEPLOY_FREEZE'
  }

  stages {

    stage('Checkout') {
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }   // 실패 지점 추적(알림용) — 각 스테이지 첫 줄 공통
        checkout scm
        script {
          // 이미지 추적·롤백용 짧은 커밋 해시. 배포 후 "무엇이 떠 있나"를 커밋으로 식별.
          env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short=8 HEAD').trim()
          // 알림용 — 이 브랜치 마지막 커밋의 작성자(= 사실상 푸시한 사람)
          env.GIT_AUTHOR = sh(returnStdout: true, script: 'git log -1 --format=%an').trim()

          // ── 배포 대상 결정 (compose | k3s) ────────────────────────────────
          // 여기서 한 번만 정하고 이후 스테이지는 env.DEPLOY_TARGET 만 본다.
          //   "어디에 배포되는가"가 로그 첫머리에 반드시 남아야 한다 — 컷백 기간에 가장 흔한
          //   사고가 "배포는 성공했는데 엉뚱한 런타임에 갔다"이기 때문이다.
          def target = (params.DEPLOY_TARGET ?: 'auto')
          if (target == 'auto') {
            target = 'compose'                               // 컷백 기간 fail-safe: 파일이 없어도 죽은 k3s 가 아니라 현재 현실(compose)로 (2026-08-08)
            if (fileExists(env.DEPLOY_TARGET_FLAG)) {
              // 읽기 실패가 빌드를 죽이지 않게 한다(플래그가 root 600 으로 만들어질 수 있다).
              try {
                def v = readFile(env.DEPLOY_TARGET_FLAG).trim()
                if (v) { target = v }
              } catch (err) {
                echo "⚠️ DEPLOY_TARGET 플래그를 읽지 못했다(compose 로 진행): ${err.message}"
              }
            }
          }
          if (!(target in ['compose', 'k3s'])) {
            error "알 수 없는 DEPLOY_TARGET='${target}' — compose 또는 k3s 여야 한다 (${env.DEPLOY_TARGET_FLAG} 확인)"
          }
          env.DEPLOY_TARGET = target

          echo "브랜치=${env.BRANCH_NAME ?: 'N/A'} · 이미지태그(SHA)=${env.IMAGE_TAG} · 작성자=${env.GIT_AUTHOR} · 배포대상=${env.DEPLOY_TARGET}"
        }
      }
    }

    stage('Compose Preflight') {
      // when 없음 = 모든 브랜치. MR 빌드에서 미리 잡아야 develop 머지 후 장애를 막는다.
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 리포지토리 상대경로를 "호스트 마운트"로 쓰는 선언을 금지한다.
        // reason: 이 파이프라인은 Jenkins 컨테이너 안에서 호스트 도커 데몬을 호출한다(Docker-out-of-Docker).
        //   compose 의 상대경로는 Jenkins 컨테이너 안 워크스페이스 기준으로 해석되지만 마운트는 호스트가 한다.
        //   호스트에 없는 경로엔 도커가 빈 디렉터리를 만들어 붙여, 설정·스크립트가 조용히 사라진다.
        //   실제 사고 2회: 2026-07-22 nginx 빈 conf, 2026-07-26 minio-init exit 127(전면 중단 2회, 빌드 191·192).
        //   해법은 이미지 bake(build 컨텍스트는 tar 로 전송돼 안전) 또는 호스트 절대경로.
        //   ※ build.context 의 './' 는 마운트가 아니라 빌드 컨텍스트라 안전 — 검출 대상이 아니다.
        sh '''
          bad=$(grep -nE "^[[:space:]]*-[[:space:]]+\\./|^[[:space:]]*file:[[:space:]]*\\./" "$COMPOSE_FILE" || true)
          if [ -n "$bad" ]; then
            echo "❌ compose 에 리포지토리 상대경로 마운트가 있습니다 (DooD 경로 함정):"
            echo "$bad"
            echo "   → 파일은 이미지에 bake(build:) 하거나, 워크스페이스 밖 호스트 절대경로를 쓸 것."
            exit 1
          fi
          echo "✅ compose preflight 통과 — 상대경로 호스트 마운트 없음"
        '''
      }
    }

    stage('Secrets Preflight') {
      when { branch 'develop' }   // 시크릿은 develop(이미지 빌드·배포)에서만 쓰인다 — MR 빌드는 불필요
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // dodam-env 크리덴셜의 필수 키를 테스트(≈10분) 전에 전수 검증한다.
        // reason: 2026-07-24 빌드 114~116 — 크리덴셜 교체 중 키 누락 시 compose 보간은
        //   "처음 만난 누락 변수 1개"만 보고해, 전모 파악에 빌드 3번을 소모했다.
        //   여기서 누락 목록 전체를 한 번에 보고하고 즉시 실패시킨다.
        // 필수 목록은 compose의 `:?` 가드에서 자동 추출 — 하드코딩 금지(가드 추가 시 자동 반영).
        // ⚠️ 시크릿 값은 절대 출력하지 않는다 — 키 이름만 다룬다.
        //
        // ★ 791 이후 이 검사가 확인하는 키는 **0개일 수 있다.** 실행용 시크릿이 전부 k8s
        //   Secret/ConfigMap 으로 넘어가면서 compose 에 `:?` 가드가 남지 않았기 때문이다.
        //   "0개 확인 → 통과"는 고장이 아니라 의도된 상태다.
        //   ⚠️ 다만 `dodam-env` 는 여전히 **web 빌드 인자 4개**(NEXT_PUBLIC_*)에 쓰인다.
        //     그쪽은 `:-` 기본값이라 여기서 안 잡히고, 누락되면 빌드가 조용히 성공한 뒤
        //     브라우저에서 소셜 로그인만 깨진다. 아래 web-args 확인이 그 구멍을 메운다.
        withCredentials([file(credentialsId: 'dodam-env', variable: 'ENV_FILE')]) {
          sh '''
            required=$(grep -v "^[[:space:]]*#" "$COMPOSE_FILE" | grep -oE '\\$\\{[A-Z_]+:\\?' | tr -cd 'A-Z_\\n' | sort -u)
            missing=""
            for k in $required; do
              grep -qE "^${k}=." "$ENV_FILE" || missing="$missing $k"
            done
            if [ -n "$missing" ]; then
              echo "❌ dodam-env 시크릿에 필수 키 누락:$missing"
              echo "   → Jenkins 크리덴셜(dodam-env)을 '기존 전체 키 + 신규 키' 병합본으로 재업로드할 것."
              echo "     dodam-env는 교체가 아니라 병합이 규칙 (S15P11B209-386)"
              exit 1
            fi
            # 값이 상대경로인 키 검출 — 호스트 마운트 소스로 쓰이면 compose preflight 와 같은 사고가 난다.
            #   예: FCM_CREDENTIALS_HOST_PATH=./secrets/fcm-service-account.json (S15P11B209-619)
            #   compose 파일엔 ${VAR:-/dev/null} 로만 보여 앞 단계에서 안 잡힌다 — 값 쪽에서 막는다.
            #   ⚠️ 키 이름만 출력한다(시크릿 값 금지 · 가드레일 9절).
            relative=$(grep -E "^[A-Z_][A-Z0-9_]*=[[:space:]]*\\./" "$ENV_FILE" | cut -d= -f1 | tr '\\n' ' ' || true)
            if [ -n "$relative" ]; then
              echo "❌ dodam-env 에 상대경로 값을 가진 키: $relative"
              echo "   → 호스트 마운트 소스는 워크스페이스 밖 절대경로여야 한다(예: /opt/dodam/secrets/...)."
              exit 1
            fi
            echo "✅ 시크릿 preflight 통과 — 필수 키 $(echo "$required" | wc -w)개 확인: $(echo $required)"

            # ── web 빌드 인자 확인 (S15P11B209-791) ────────────────────────────
            # NEXT_PUBLIC_* 는 빌드 시점에 **JS 번들로 구워진다.** compose 에서 `:-` 기본값이라
            # 비어 있어도 빌드가 서지 않고, 증상은 브라우저에서 소셜 로그인 실패로만 나타난다.
            # 위 `:?` 자동 추출로는 잡히지 않으므로 여기서 이름을 직접 확인한다.
            #   ⚠️ 실패가 아니라 경고인 이유: 이 키들이 없어도 빌드·배포 자체는 성립하고(로그인만
            #      안 됨), 여기서 세우면 무관한 변경까지 배포가 막힌다. 대신 로그에 크게 남긴다.
            #      값이 실제로 번들에 들어갔는지는 배포 후 **JS 번들 실물**로 확인할 것 —
            #      서버렌더 HTML 만 보면 알 수 없다(2026-08-04 실제 오진).
            web_missing=""
            for k in NEXT_PUBLIC_KAKAO_CLIENT_ID NEXT_PUBLIC_GOOGLE_CLIENT_ID NEXT_PUBLIC_NAVER_CLIENT_ID; do
              grep -qE "^${k}=." "$ENV_FILE" || web_missing="$web_missing $k"
            done
            if [ -n "$web_missing" ]; then
              echo "⚠️  web 빌드 인자 누락(비어 있음):$web_missing"
              echo "    → 이 상태로 구운 번들은 해당 소셜 로그인이 동작하지 않는다."
              echo "      dodam-env 에 값을 채우고 web 을 다시 빌드할 것."
            else
              echo "✅ web 빌드 인자 3종 확인 — OAuth 클라이언트 ID 채워짐"
            fi
          '''
        }

        // ── compose 실행 정의용 시크릿 검증 (컷백) ─────────────────────────────
        // 위 검사는 **이미지 빌드**용 파일(build.yml)을 본다. 791 이후 그 파일에는 `:?` 가드가
        // 거의 남지 않아 "0개 확인 → 통과"가 정상이다. 그런데 컷백 배포가 실제로 쓰는 것은
        // `infra/docker-compose.yml` 이고, 이쪽에는 `:?` 가드가 수십 개다(DB 비밀번호·JWT·
        // AI 모드·PVC 경로 등). 그 파일 기준으로 dodam-env-compose 를 전수 검증한다.
        //
        // ★ 여기서 잡지 못하면 어떻게 되나: `docker compose up` 이 **첫 번째 누락 변수 하나만**
        //   보고하고 죽는다. 배포 중단 상태에서 빌드를 반복하며 하나씩 알아내야 한다
        //   (2026-07-24 빌드 114~116 이 정확히 그 낭비였다). 목록 전체를 한 번에 보고한다.
        // ⚠️ 시크릿 값은 절대 출력하지 않는다 — 키 이름과 경로만 다룬다.
        script {
          if (env.DEPLOY_TARGET == 'compose') {
            withCredentials([file(credentialsId: 'dodam-env-compose', variable: 'COMPOSE_ENV_FILE')]) {
              sh '''
                required=$(grep -v "^[[:space:]]*#" "$COMPOSE_RUN_FILE" | grep -oE '\\$\\{[A-Z_]+:\\?' | tr -cd 'A-Z_\\n' | sort -u)
                missing=""
                for k in $required; do
                  grep -qE "^${k}=." "$COMPOSE_ENV_FILE" || missing="$missing $k"
                done
                if [ -n "$missing" ]; then
                  echo "❌ dodam-env-compose 시크릿에 필수 키 누락:$missing"
                  echo "   → 서버의 infra/.env.compose 를 그대로 Jenkins 크레덴셜(dodam-env-compose)로 재업로드할 것."
                  echo "     두 파일은 **같은 내용이어야 한다** — 갈라지면 사람이 손으로 띄운 스택과"
                  echo "     파이프라인이 띄운 스택의 설정이 달라진다(가장 찾기 어려운 종류의 사고)."
                  exit 1
                fi
                echo "✅ compose 실행 시크릿 preflight 통과 — 필수 키 $(echo "$required" | wc -w)개 확인"

                # 호스트 마운트 소스로 쓰이는 경로 3종은 **절대경로**여야 한다.
                #   상대경로면 Jenkins 컨테이너 안 워크스페이스 기준으로 해석되는데 마운트는
                #   호스트가 한다 → 도커가 빈 디렉터리를 만들어 붙이고 설정이 조용히 사라진다
                #   (2026-07-22 nginx 빈 conf · 2026-07-26 minio-init exit 127 과 같은 함정).
                bad=""
                for k in PVC_ROOT NGINX_CONF_DIR MONGO_INITDB_DIR FCM_CREDENTIALS_HOST_PATH; do
                  # 값이 홑/겹따옴표로 감싸여 있을 수 있다(.env.compose 는 홑따옴표 스타일).
                  #   앞쪽 따옴표만 떼면 절대경로 판정에는 충분하다. 값은 출력하지 않는다.
                  v=$(grep -E "^${k}=" "$COMPOSE_ENV_FILE" | tail -1 | cut -d= -f2- | sed "s/^'//" | sed 's/^"//')
                  [ -z "$v" ] && continue
                  case "$v" in /*) : ;; *) bad="$bad $k" ;; esac
                done
                if [ -n "$bad" ]; then
                  echo "❌ 상대경로 값을 가진 키:$bad — 호스트 절대경로여야 한다."
                  exit 1
                fi
                echo "✅ 호스트 경로 키 절대경로 확인"
              '''
            }
          }
        }
      }
    }

    stage('Migration Preflight') {
      // when 없음 = 모든 브랜치. MR 빌드에서 잡아야 의미가 있다 — 머지된 뒤에 알면 늦다.
      // reason: Flyway 는 같은 버전이 둘이면 마이그레이션이 아니라 **애플리케이션 기동**이 실패한다
      //   (`Found more than one migration with version N`). 그런데 파일명이 다르므로 git 은 충돌로
      //   보지 않는다 — 양쪽 다 "새 파일 추가"라 조용히 병합된다.
      //   실제 사고 2026-08-06: 982 와 983 이 각각 V43 을 만들었고, 텍스트 충돌은 테스트 주석
      //   한 줄에서만 났다. 정작 위험한 중복은 아무 경고 없이 통과했다.
      //   DatabaseMigrationIntegrationTest 가 결국 잡지만 그건 Testcontainers 를 띄우는 무거운
      //   테스트라 로컬에서 잘 안 돌리고, 무엇보다 develop 에 머지된 뒤에 터진다.
      // ※ 구조적으로 재발한다: 번호는 브랜치를 딸 때 정해지는데 머지는 며칠 뒤라,
      //   분기 시점에 비어 있던 번호가 머지 시점에는 차 있다.
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // origin/develop 이 없으면 스크립트가 교차 검사를 건너뛰고 경고만 남긴다(브랜치 내부
        //   중복 검사는 그대로 수행). 얕은 클론에서 파이프라인이 죽지 않게 하려는 것이다.
        sh '''
          git fetch --no-tags --quiet origin develop:refs/remotes/origin/develop 2>/dev/null || true
          chmod +x infra/scripts/check-migration-versions.sh
          infra/scripts/check-migration-versions.sh
        '''
      }
    }

    stage('Build & Test — backend') {
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        dir('backend') {
          // 테스트를 여기서 돌린다(이미지 빌드는 -x test로 스킵). 실패 시 파이프라인 중단 = 배포 안 함.
          // clean 제거 + --build-cache: 워크스페이스가 브랜치별로 재사용되므로 증분 컴파일 활용
          //   (S15P11B209-391 — clean은 매번 풀컴파일을 강제해 2~4분 낭비였음)
          // test와 bootJar를 한 Gradle 호출로 산출(Phase 2): 테스트용 컴파일 결과를 bootJar가
          //   그대로 재사용하므로 이미지 빌드에서 재컴파일하지 않는다(이중 컴파일 제거).
          //   backend/build/libs/*.jar 를 Docker가 COPY만 한다(backend/Dockerfile 참조).
          sh 'chmod +x gradlew && ./gradlew --no-daemon --build-cache test bootJar'
        }
      }
      post {
        // 성공/실패 무관하게 테스트 리포트 수집(Jenkins UI에 추이 표시)
        always {
          junit testResults: 'backend/build/test-results/test/*.xml', allowEmptyResults: true
        }
      }
    }

    stage('Test — app (flutter)') {
      // 앱 코드가 바뀐 빌드에서만 돈다 (S15P11B209-642).
      //   reason: 빌더 이미지가 5GB 이고 테스트에 1~2분이 든다. 백엔드만 고친 푸시마다
      //   앱 테스트를 도는 건 낭비다. FORCE_APP_TESTS 로 언제든 강제 실행할 수 있다.
      //   ⚠️ Multibranch 는 첫 빌드에 changeset 이 비어 있을 수 있다(비교 대상 이전 빌드 없음).
      //      그 경우 스킵되는 게 정상이고, 다음 빌드부터 정상 판정된다.
      when {
        anyOf {
          changeset 'frontend/mobile/**'
          expression { params.FORCE_APP_TESTS }
        }
      }
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 실행 실체는 infra/mobile/ci-test.sh — 호스트에서도 같은 명령으로 재현된다.
        //   bind mount 를 쓰지 않는 이유(DooD 경로 함정)는 스크립트 주석 참조.
        sh 'infra/mobile/ci-test.sh'
      }
    }

    stage('Docker Build') {
      when { branch 'develop' }      // develop만 이미지 빌드 — 브랜치 빌드가 :local을 덮어 배포 레이스 만드는 것 차단
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 앱 이미지(backend·ai)를 호스트 도커에 바로 빌드(레지스트리 없음). 배포는 :local 사용.
        // 빌드 후 :<SHA> 태그도 부여 → 불변 복원지점(롤백=190에서 이 태그로 되돌림).
        // Compose는 build만 실행해도 전체 파일의 필수 변수를 먼저 보간하므로 배포와 같은 Secret File이 필요하다.
        withCredentials([file(credentialsId: 'dodam-env', variable: 'ENV_FILE')]) {
          sh '''
            docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build
            docker tag dodam-backend:local dodam-backend:${IMAGE_TAG}
            docker tag dodam-ai:local      dodam-ai:${IMAGE_TAG}
            docker tag dodam-nginx:local   dodam-nginx:${IMAGE_TAG}
            docker tag dodam-web:local     dodam-web:${IMAGE_TAG}
          '''
        }
      }
    }

    stage('Test — ai (import smoke)') {
      when { branch 'develop' }      // 빌드된 이미지가 필요해 Docker Build와 세트로 develop 전용
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // ai는 아직 유닛테스트 없음 → 빌드된 이미지에서 앱이 import 되는지만 확인. (TODO: 실제 테스트 추가)
        sh 'docker run --rm dodam-ai:local python -c "import main; print(\'ai import OK\')"'
      }
    }

    stage('배포 프리즈 안내') {
      // 프리즈 중이라는 사실을 로그와 알림에 남긴다. 조용히 건너뛰면 "성공"만 보고
      // 배포된 줄 안다 — 거짓 초록불이 빨간불보다 위험하다.
      when {
        branch 'develop'
        expression { fileExists(env.DEPLOY_FREEZE_FLAG) }
      }
      steps {
        script {
          env.DEPLOY_FROZEN = 'true'
          // 사유 읽기는 실패해도 빌드를 죽이지 않는다 — 플래그가 root 600 으로 만들어지면
          // readFile 이 예외를 던진다. 배포를 멈추려는 장치가 빌드 전체를 깨면 본말전도다.
          def reason = ''
          try {
            reason = '\n' + readFile(env.DEPLOY_FREEZE_FLAG).trim()
          } catch (err) {
            reason = "\n(사유 파일을 읽지 못함: ${err.message})"
          }
          echo "⏸️ 배포 프리즈 — 이 빌드는 배포·헬스체크를 건너뛴다.${reason}"
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Deploy — 대상에 따라 둘 중 하나만 실행된다 (env.DEPLOY_TARGET, 파일 헤더 ★★ 절)
    // ═══════════════════════════════════════════════════════════════════════

    stage('Deploy — compose (develop only)') {
      when {
        branch 'develop'
        expression { env.DEPLOY_TARGET == 'compose' }
        expression { !fileExists(env.DEPLOY_FREEZE_FLAG) }
      }
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // ⚠️⚠️ **compose 에는 롤링 배포가 없다.** k3s 의 backend 는 replicas 2 + maxUnavailable 0
        //   + preStop 8s 로 무중단이었지만(362 실증), compose 는 컨테이너를 지우고 다시 만든다.
        //   즉 **이 스테이지는 반드시 순단을 만든다.** 예상 폭:
        //     · backend  재기동 → readiness 까지 약 40~120초 (그동안 /api 는 502)
        //     · web·ai   재기동 → 각 10~60초
        //     · nginx    재생성 → 1~3초 (연결 리셋)
        //   없앨 수는 없고 **줄이는 순서**만 고를 수 있다. 아래 3단계가 그 순서다.
        //   발표·시연 중에는 develop 머지를 하지 말 것(= 이 스테이지가 도는 것이 곧 순단이다).
        withCredentials([file(credentialsId: 'dodam-env-compose', variable: 'COMPOSE_ENV_FILE')]) {
          sh '''
            set -e

            # ── 0. 이미지 → 로컬 레지스트리 ───────────────────────────────────
            # compose 실행 정의가 `127.0.0.1:5000/dodam-*:${IMAGE_TAG}` 를 참조하므로
            #   push 는 추적성 문제가 아니라 **배포의 전제**다(이 단계가 빠지면 pull 실패).
            # :prod 도 함께 갱신한다 — k3s 로 되돌아갔을 때 매니페스트 기본값(:prod)이
            #   옛 이미지를 가리켜 **조용히 과거로 롤백**되는 것을 막는다(771 과 같은 사유).
            infra/scripts/push-staging-images.sh --tag "$IMAGE_TAG" --with-ai --with-web
            infra/scripts/push-staging-images.sh --tag prod         --with-ai --with-web

            # ── 1. 앱 3종(backend·ai·web): 단일 노드형 **블루-그린 무중단 배포** ───────
            # 각 서비스를 유휴 색으로 새 태그에 띄워 **내부 헬스체크 통과 후** nginx 스위치만
            #   넘긴다(upstream-active.conf 재작성 + reload). 그 다음 옛 색을 정지한다.
            #   → 사용자 순단 없음(무중단 *배포*). 상시 이중화는 아니다 — 정상 상태엔 활성 색 1벌.
            # 실체는 infra/scripts/bluegreen-deploy.sh 하나(사람이 호스트에서 돌리는 것과 동일 로직).
            #
            # ⚠️⚠️ DooD — 이 스위치는 반드시 **호스트 파일**을 써야 한다.
            #   dodam-jenkins 에는 host repo(/home/kr/S15P11B209)가 **안 보인다**(docker.sock +
            #   jenkins-home 만 마운트). 그런데 스위치가 바꾸는 upstream-active.conf 는 운영 nginx 에
            #   **라이브 바인드**돼 있고(NGINX_CONF_DIR), .env.active 는 활성 색 상태 파일이다.
            #   Jenkins 워크스페이스 사본에 쓰면 nginx 에 반영되지 않는다. 그래서 스크립트를
            #   **host repo 를 절대경로로 bind-mount 한 throwaway 컨테이너** 안에서 실행한다.
            #   (이미지가 아니라 config 는 호스트가 관리하는 기존 모델 — nginx conf 마운트 — 과 동일.)
            #   ⚠️ 따라서 블루-그린 로직(스크립트·compose·nginx conf)의 기준은 **호스트 체크아웃**
            #     이지 이 빌드의 워크스페이스가 아니다. 로직을 바꾸려면 host /home/kr/S15P11B209 갱신.
            HOST_REPO=/home/kr/S15P11B209
            HOST_UID=1004; HOST_GID=1004                  # host repo 소유자(kr). `stat -c %u:%g infra` 로 확인.
            SOCK_GID=$(stat -c '%g' /var/run/docker.sock)  # docker.sock 그룹 — 비-root uid 의 소켓 접근용(현재 988)
            bg() {   # $@ = bluegreen-deploy.sh 인자 (<서비스> <태그>)
              # ★ --entrypoint bash: dodam-jenkins:local 의 jenkins 엔트리포인트가 uid 1004 로
              #   /var/jenkins_home 에 쓰려다 죽던 것을 우회(2026-08-08 빌드321 Deploy 실패 원인).
              docker run --rm \
                --entrypoint bash \
                --user "${HOST_UID}:${HOST_GID}" --group-add "$SOCK_GID" \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v "$HOST_REPO/infra":/repo/infra \
                -e COMPOSE_FILE=/repo/infra/docker-compose.yml \
                -e ENV_COMPOSE=/repo/infra/.env.compose \
                -e ENV_ACTIVE=/repo/infra/.env.active \
                -e UPSTREAM_CONF=/repo/infra/nginx/conf.d.compose/upstream-active.conf \
                -e IMAGE_TAG="$IMAGE_TAG" \
                dodam-jenkins:local \
                /repo/infra/scripts/bluegreen-deploy.sh "$@"
            }
            # 데이터 계층(mysql·mongo·redis·minio)은 스크립트가 --no-deps 로 절대 건드리지 않는다.
            bg backend "$IMAGE_TAG"
            bg ai      "$IMAGE_TAG"
            bg web     "$IMAGE_TAG"

            # ── 2. nginx 자체: **기존 방식 유지**(블루-그린 대상 아님) ────────────────
            # nginx 이미지/conf 갱신은 재생성으로 반영한다. 블루-그린 스위치가 이미 upstream 을
            #   바꿔 reload 했으므로, 이미지가 안 바뀌면 아래 up 은 no-op 이다. 바뀌면 재생성
            #   (1~3s 순단) — 앱과 달리 nginx 는 단일 인스턴스라 이 짧은 순단은 기존과 동일하게 감수.
            #   --no-deps 로 데이터·앱 색을 건드리지 않고 nginx 만 다룬다.
            TAG_ENV=.compose-image-tag.env
            printf 'IMAGE_TAG=%s\\n' "$IMAGE_TAG" > "$TAG_ENV"
            RECREATE=""
            [ "${COMPOSE_FORCE_RECREATE:-false}" = "true" ] && RECREATE="--force-recreate"
            docker compose -f "$COMPOSE_RUN_FILE" --env-file "$COMPOSE_ENV_FILE" --env-file "$TAG_ENV" \
              up -d --no-deps $RECREATE nginx
            # 스위치가 이미 reload 했지만, nginx 가 재생성됐을 수도 있어 한 번 더 reload(무해한 no-op).
            docker exec dodam-nginx nginx -s reload \
              && echo "   ✅ nginx reload" \
              || echo "   ⚠️ nginx reload 실패(설정 오류 가능) — Healthcheck e2e 로 판단한다"

            echo "✅ 블루-그린 배포 완료(backend·ai·web 무중단) + nginx 반영 — 태그 :$IMAGE_TAG"
          '''
        }
      }
    }

    stage('Deploy — k3s (develop only)') {
      // ★ 컷백 이후에도 이 스테이지를 **지우지 않는다.** k3s 로 되돌아가는 순간 그대로 되살아나야
      //   하기 때문이다. 컷백이 실패했을 때 파이프라인까지 다시 고치는 상황을 만들지 않는다.
      when {
        branch 'develop'
        expression { env.DEPLOY_TARGET == 'k3s' }
        expression { !fileExists(env.DEPLOY_FREEZE_FLAG) }
      }
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // ★ 2026-07-29 컷오버(S15P11B209-360) 이후 배포 대상이 compose → k3s 로 바뀌었다.
        //   이전 구현은 `docker compose up -d` 였다. 그대로 두면 compose nginx 가 다시 떠서
        //   k8s gateway 와 호스트 80/443 을 두고 충돌한다 — 배포가 곧 장애가 된다.
        //
        //   kubeconfig 는 cluster-admin 이 아니라 네임스페이스 한정 ServiceAccount 다.
        //   생성·삭제 권한이 없어 `set image` 와 rollout 조회만 할 수 있다(359).
        //   워크로드 생성은 사람이 `kubectl apply -k` 로 한다.
        withCredentials([file(credentialsId: 'dodam-kubeconfig', variable: 'DEPLOYER_KUBECONFIG')]) {
          sh '''
            set -e
            export KUBECONFIG="$DEPLOYER_KUBECONFIG"

            # containerd 는 도커 이미지 저장소를 보지 못한다 → 로컬 레지스트리를 경유한다.
            #   :prod 도 함께 갱신하는 이유: 매니페스트가 :prod 를 가리키므로, 갱신하지 않으면
            #   나중에 누가 `kubectl apply -k overlays/prod` 를 돌렸을 때 **옛 이미지로
            #   조용히 되돌아간다.** SHA 태그는 추적용, :prod 는 매니페스트 기본값용이다.
            #
            #   ★ 이 갱신은 방어의 **절반**이다 (S15P11B209-771).
            #     레지스트리 :prod 를 아무리 최신으로 맞춰도, 파드가 기본값 IfNotPresent 로
            #     뜨면 kubelet 은 **노드에 캐시된 옛 :prod** 를 재풀 없이 쓴다.
            #     나머지 절반이 base 매니페스트의 `imagePullPolicy: Always` 다.
            #     둘 중 하나만 있으면 막히지 않는다 — 2026-08-02·08-04 두 번 그렇게 터졌다.
            infra/scripts/push-staging-images.sh --tag "$IMAGE_TAG" --with-ai --with-web
            infra/scripts/push-staging-images.sh --tag prod         --with-ai --with-web

            # 컨테이너 이름은 Deployment 이름과 다를 수 있다 — gateway 의 컨테이너는 nginx 다.
            kubectl -n dodam set image deployment/backend backend=127.0.0.1:5000/dodam-backend:"$IMAGE_TAG"
            kubectl -n dodam set image deployment/gateway nginx=127.0.0.1:5000/dodam-nginx:"$IMAGE_TAG"
            kubectl -n dodam set image deployment/ai      ai=127.0.0.1:5000/dodam-ai:"$IMAGE_TAG"
            kubectl -n dodam set image deployment/web     web=127.0.0.1:5000/dodam-web:"$IMAGE_TAG"

            # backend 는 replicas 2 + maxUnavailable 0 + preStop 8s 로 무중단이다(362 실증).
            kubectl -n dodam rollout status deployment/backend --timeout=300s
            kubectl -n dodam rollout status deployment/gateway --timeout=300s
            kubectl -n dodam rollout status deployment/ai      --timeout=300s
            # ★ web 은 gateway 보다 먼저 준비돼야 한다. 순서가 어긋나면 gateway 가 새 conf 로
            #   뜬 뒤 web 이 아직 없어 `/` 가 잠깐 502 가 된다. rollout status 로 기다린다.
            kubectl -n dodam rollout status deployment/web     --timeout=300s
          '''
        }
      }
    }

    stage('Healthcheck') {
      // 프리즈 시 같이 막는다 — 배포를 건너뛴 채 헬스체크만 돌면 "직전 배포"가 건강하다는
      // 뜻일 뿐인데 이번 빌드가 검증된 것처럼 초록불이 뜬다.
      when {
        branch 'develop'
        expression { !fileExists(env.DEPLOY_FREEZE_FLAG) }
      }
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // ── ① 런타임이 실제로 준비됐는가 (대상별로 보는 신호가 다르다) ─────────
        script {
          if (env.DEPLOY_TARGET == 'compose') {
            withCredentials([file(credentialsId: 'dodam-env-compose', variable: 'COMPOSE_ENV_FILE')]) {
              sh '''
                set -e
                TAG_ENV=.compose-image-tag.env
                printf 'IMAGE_TAG=%s\\n' "$IMAGE_TAG" > "$TAG_ENV"
                compose() { docker compose -f "$COMPOSE_RUN_FILE" --env-file "$COMPOSE_ENV_FILE" --env-file "$TAG_ENV" "$@"; }

                echo "── docker compose ps ──"
                compose ps

                fail=0
                # 컨테이너 health 를 **즉시 1회가 아니라 healthy 될 때까지 폴링**한다.
                #   nginx 는 배포마다 재생성돼 Healthcheck 가 도는 순간 아직 start_period 의
                #   'starting' 이라, 단발 검사로는 배포가 성공해도 오탐한다(2026-08-08 빌드324~
                #   반복 실패 + 색 churn 의 실제 원인 — backend/ai/web 은 deploy 의 wait_healthy 로
                #   이미 healthy 였지만 nginx 만 기다려주지 않았다).
                hc_status() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
                hc_wait() {   # $1=컨테이너 · 상태 echo · healthy 면 return 0 (최대 ~60초)
                  _i=0
                  while : ; do
                    _st=$(hc_status "$1")
                    case "$_st" in
                      healthy)           echo "$_st"; return 0 ;;
                      unhealthy|missing) echo "$_st"; return 1 ;;
                    esac
                    _i=$((_i+1)); [ "$_i" -ge 30 ] && { echo "$_st"; return 1; }
                    sleep 2
                  done
                }
                # (a) 앱 — healthy 를 요구한다. "떠 있다"와 "받을 준비가 됐다"는 다르다.
                #     ★ 블루-그린이라 backend/ai/web 은 **활성 색 컨테이너**를 docker ps 로 찾는다
                #        (정상 상태엔 색당 1벌만 running · 옛/유휴 색은 정지). nginx 는 단일.
                for svc in backend ai web; do
                  c=$(docker ps --filter "name=dodam-${svc}-" --filter "status=running" --format '{{.Names}}' | head -1)
                  if [ -z "$c" ]; then echo "   ❌ dodam-${svc}-* 활성 색 컨테이너 없음"; fail=1; continue; fi
                  if st=$(hc_wait "$c"); then echo "   ✅ $c $st"; else echo "   ❌ $c $st"; fail=1; fi
                done
                if st=$(hc_wait dodam-nginx); then echo "   ✅ dodam-nginx $st"; else echo "   ❌ dodam-nginx $st"; fail=1; fi
                # (b) 데이터 4종 — running 이면 된다. 이 스테이지가 배포한 대상이 아니지만,
                #     하나라도 빠지면 위 앱이 조용히 반쪽으로 동작하므로 함께 단언한다.
                #     ⚠️ mongodb 는 start_period 300s 라 기동 직후 health=starting 이 정상이다.
                for c in dodam-mysql dodam-mongodb dodam-redis dodam-minio; do
                  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
                  h=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$c" 2>/dev/null || echo -)
                  if [ "$st" = "running" ]; then echo "   ✅ $c $st(health=$h)"; else echo "   ❌ $c $st"; fail=1; fi
                done
                # (c) ★ 태그가 아니라 **다이제스트**로 확인한다.
                #     "배포가 성공했다"와 "새 이미지가 떠 있다"는 다르다. 재생성을 건너뛰면
                #     옛 컨테이너가 그대로 남는데, 태그만 보면 드러나지 않는다(2026-08-04 착시).
                #     블루-그린이라 backend/ai/web 은 **활성 색 컨테이너**로 대조한다.
                for svc in backend ai web; do
                  c=$(docker ps --filter "name=dodam-${svc}-" --filter "status=running" --format '{{.Names}}' | head -1)
                  want=$(docker image inspect -f '{{.Id}}' "127.0.0.1:5000/dodam-$svc:$IMAGE_TAG" 2>/dev/null || echo want-missing)
                  got=$(docker inspect -f '{{.Image}}' "$c" 2>/dev/null || echo got-missing)
                  if [ "$want" = "$got" ]; then
                    echo "   ✅ $c 이미지 다이제스트 일치"
                  else
                    echo "   ❌ ${c:-dodam-$svc-?} 이미지 불일치 — 기대=$want 실제=$got"
                    echo "      → 블루-그린 전환이 새 색을 안 띄웠거나 옛 색이 남았다. 스위치 로그 확인."
                    fail=1
                  fi
                done
                # nginx(단일) — 기존 방식이라 같은 SHA 재배포 시 재생성이 안 될 수 있다.
                want=$(docker image inspect -f '{{.Id}}' "127.0.0.1:5000/dodam-nginx:$IMAGE_TAG" 2>/dev/null || echo want-missing)
                got=$(docker inspect -f '{{.Image}}' dodam-nginx 2>/dev/null || echo got-missing)
                if [ "$want" = "$got" ]; then
                  echo "   ✅ dodam-nginx 이미지 다이제스트 일치"
                else
                  echo "   ❌ dodam-nginx 이미지 불일치 — 기대=$want 실제=$got"
                  echo "      → 같은 SHA 재배포로 nginx 재생성이 안 된 경우. COMPOSE_FORCE_RECREATE=true 로 재실행."
                  fail=1
                fi
                [ "$fail" = "0" ] || exit 1
              '''
            }
          } else {
            // ⚠️ rollout status 만으로는 부족하다 — **replicas 0 인 워크로드에서 즉시 성공**한다.
            //    "롤아웃 성공"과 "떠 있는 파드가 있다"는 다른 말이다(S15P11B209-359 교훈).
            withCredentials([file(credentialsId: 'dodam-kubeconfig', variable: 'DEPLOYER_KUBECONFIG')]) {
              sh '''
                set -e
                export KUBECONFIG="$DEPLOYER_KUBECONFIG"
                fail=0
                for d in backend gateway ai web; do
                  ready="$(kubectl -n dodam get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
                  ready="${ready:-0}"
                  if [ "$ready" -ge 1 ]; then
                    echo "   ✅ $d readyReplicas=$ready"
                  else
                    echo "   ❌ $d readyReplicas=$ready — 롤아웃은 끝났다지만 Ready 인 파드가 없다"
                    fail=1
                  fi
                done
                [ "$fail" = "0" ] || exit 1
              '''
            }
          }
        }
        // ── ② 공개 도메인 e2e (대상 공통) ────────────────────────────────────
        // 컨테이너 안에서 127.0.0.1 을 치지 않는다. **사용자가 실제로 지나는 경로**를 통째로 친다:
        //   compose : DNS → 공개 IP → 호스트 80/443 → nginx 컨테이너 → backend/ai/web
        //   k3s     : DNS → 공개 IP → hostPort → gateway 파드 → backend/ai/web
        // 두 경로 모두 같은 공개 도메인을 지나므로 **이 검사만은 대상과 무관하게 동일**하다.
        //   ⚠️ NodePort(30080/30443)로 검증하지 않는다. 이 호스트에서는 k3s 가 꺼져 있어도
        //      응답이 오기 때문에 스테이징과 운영을 구분하지 못한다(2026-07-29 실측).
        //   ★ 이 단계가 "배포됐다"와 "동작한다"를 가르는 유일한 관문이다. 컷백 직후에는
        //      런타임이 통째로 바뀌므로 여기서 처음 드러나는 결함이 있을 수 있다.
        sh '''
          set -e
          base=https://i15b209.p.ssafy.io
          check() {   # $1=경로  $2=기대코드
            for i in $(seq 1 10); do
              code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$base$1" || echo 000)
              [ "$code" = "$2" ] && { echo "   ✅ $1 → $code"; return 0; }
              sleep 3
            done
            echo "   ❌ $1 → $code (기대 $2)"; return 1
          }
          fail=0
          # / 는 769 의 랜딩이다(302 임시 페이지 → 383 리다이렉트 307 → 769 랜딩 200).
          # 랜딩과 커뮤니티는 다른 파드 경로가 아니라 같은 web 컨테이너의 두 라우트다 —
          # 둘 다 단언해야 "web 이 떠 있다"와 "라우팅이 온전하다"를 함께 검증한다.
          check /                 200 || fail=1
          check /community        200 || fail=1
          check /ai/health        200 || fail=1
          check /api/v1/children  401 || fail=1   # 무토큰 차단 = 인증이 살아 있다는 뜻
          check /legal/privacy/   200 || fail=1   # 스토어 심사 URL — 웹 전환 후에도 살아야 한다(383)

          # ── compose 전용 추가 검증 ─────────────────────────────────────────
          # 내부 계약 스키마(FastAPI 문서)가 외부에 열려 있지 않은지 본다.
          #   compose 는 conf 를 `infra/nginx/conf.d.compose/` 에서 **마운트**하므로 이 차단이
          #   이미지가 아니라 파일에 달려 있다 — 파일이 바뀌면 조용히 열릴 수 있다.
          #   k3s 경로에 걸지 않는 이유: 라이브 ConfigMap 에는 아직 이 블록이 반영돼 있지 않다
          #   (git 쪽만 앞서 있음). 롤백 시 `kubectl apply -k` 로 반영한 뒤 여기에도 추가할 것.
          if [ "$DEPLOY_TARGET" = "compose" ]; then
            check /ai/docs         404 || fail=1
            check /ai/openapi.json 404 || fail=1
            check /ai/redoc        404 || fail=1
          fi

          [ "$fail" = "0" ] || { echo "  ✗ 공개 e2e 실패 — 롤백 판단 지점"; exit 1; }
          echo "✅ $DEPLOY_TARGET 배포 정상 + 공개 경로 e2e 통과"
        '''
      }
    }

    stage('Build — android AAB') {
      when { expression { params.BUILD_ANDROID_AAB } }   // 요청했을 때만. 기본은 건너뛴다.
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 배포(Deploy·Healthcheck) 뒤에 둔 이유: AAB 는 서버 배포와 무관한데 앞에 두면
        //   빌드가 수 분 길어지는 만큼 배포가 늦어진다. 여기서 실패해도 이미 배포는 끝나 있다.
        //
        // ⚠️ 서명 자재 3종은 전부 Credentials(secret file)다. 저장소엔 절대 두지 않는다.
        //   - dodam-android-keystore       : 업로드 keystore(.jks)
        //   - dodam-android-key-properties : storeFile·storePassword·keyAlias·keyPassword
        //   - dodam-mobile-oauth-env       : KAKAO_NATIVE_APP_KEY 등 5개 (KEY=VALUE)
        //   ※ storeFile 값은 컨테이너 안 경로 `upload-keystore.jks` 여야 한다
        //     (build-aab.sh 가 /src/android/ 로 넣는다). 호스트 경로를 적으면 못 찾는다.
        withCredentials([
          file(credentialsId: 'dodam-android-keystore',       variable: 'ANDROID_KEYSTORE'),
          file(credentialsId: 'dodam-android-key-properties', variable: 'ANDROID_KEY_PROPS'),
          file(credentialsId: 'dodam-mobile-oauth-env',       variable: 'MOBILE_OAUTH_ENV')
        ]) {
          // build-aab.sh 는 bind mount 를 쓰지 않는다(DooD 경로 함정 회피 — 스크립트 주석 참조).
          sh '''
            set -e
            # ⚠️ Jenkins 는 BUILD_NUMBER(= 잡 빌드 카운터)를 셸 환경에 자동으로 주입한다.
            #   그대로 두면 build-aab.sh 가 그 값을 versionCode 로 쓴다. 그런데 이 카운터는
            #   저장소가 아니라 **잡에 딸린 상태**라, 잡이 지워지면 1 부터 다시 시작한다.
            #   2026-07-29 실제로 그 일이 있었다(123+ → 1). Play 는 versionCode 가 뒤로 구르면
            #   그 앱의 업로드를 영구히 거부한다 — 그래서 저장소 기준 값으로 덮어써서 넘긴다.
            #   (S15P11B209-629 · 산출 근거는 infra/mobile/app-version.sh 헤더)
            BUILD_NAME="$(infra/mobile/app-version.sh --build-name)"
            BUILD_NUMBER="$(infra/mobile/app-version.sh --build-number)"
            echo "앱 버전: versionName=${BUILD_NAME} · versionCode=${BUILD_NUMBER}"
            KEYSTORE_FILE="$ANDROID_KEYSTORE" \
            KEY_PROPERTIES_FILE="$ANDROID_KEY_PROPS" \
            OAUTH_ENV_FILE="$MOBILE_OAUTH_ENV" \
            REQUIRE_RELEASE_SIGNING=true \
            BUILD_NAME="$BUILD_NAME" \
            BUILD_NUMBER="$BUILD_NUMBER" \
            infra/mobile/build-aab.sh
          '''
        }
      }
      post {
        success {
          // AAB 는 Play 에 올릴 산출물이라 빌드 이력에 남긴다. 서명 리포트도 함께 보관해
          // "어느 키로 서명됐는지"를 나중에 확인할 수 있게 한다(비밀번호는 들어 있지 않다).
          archiveArtifacts artifacts: 'build-artifacts/app-release.aab, build-artifacts/signing-report.txt',
                           fingerprint: true, allowEmptyArchive: false
        }
      }
    }
  }

  post {
    success {
      echo "✅ 파이프라인 성공 (배포 이미지 태그=${env.IMAGE_TAG})"
      script { notifyMattermost('✅', '빌드 성공') }
    }
    failure {
      // ⚠️ "미배포"라고 단정하지 않는다. Deploy·Healthcheck 뒤에도 스테이지가 있어
      //    (k3s 선검증 · AAB), 배포가 멀쩡히 끝난 뒤 실패하는 경우가 실제로 잦다.
      //    2026-07-29 빌드 15·16·18 이 모두 그랬는데 로그는 "미배포"라고 말했다 —
      //    사실과 다른 안내는 사람을 엉뚱한 곳부터 뒤지게 만든다.
      echo "❌ 실패 — 실패 지점: ${env.CURRENT_STAGE ?: '?'} · 배포 여부는 위 Deploy/Healthcheck 스테이지 결과로 판단할 것."
      script { notifyMattermost('❌', '빌드 실패') }
    }
    always  {
      // 이미지 보존정책(S15P11B209-391): SHA 태그는 서비스별 최신 3세대만 유지(:local 불가침).
      //   reason: 무조건 `image prune -f`는 빌드 캐시를 파괴해 콜드 빌드(타임아웃 경주)를 유발했고,
      //   SHA 태그는 프룬 대상이 아니라 무한 누적됐다(07/24 실측 268개·62GB → 1회 정리 후 이 정책으로 유지).
      //   dangling 프룬은 until=24h 필터로 최근 캐시 레이어를 보존한다.
      sh '''
        for repo in dodam-backend dodam-ai dodam-nginx; do
          docker images --format '{{.Repository}}:{{.Tag}}' "$repo" 2>/dev/null \
            | grep -v ':local' | tail -n +4 | xargs -r docker rmi >/dev/null 2>&1 || true
        done
        docker image prune -f --filter "until=24h" >/dev/null 2>&1 || true
      '''
    }
  }
}
