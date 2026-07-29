// 도담 CI/CD 파이프라인 — 단일 EC2 · 레지스트리 없이 로컬 빌드 · develop 배포
// 관련 이슈: S15P11B209-189 (Jenkins CI/CD)
//
// 잡 유형: Multibranch Pipeline 권장(브랜치 자동 감지 → env.BRANCH_NAME 세팅). Deploy는 develop에서만.
// 전제:
//   - Jenkins 컨트롤러에 docker CLI + compose 플러그인 + 호스트 docker.sock (infra/jenkins/ 이미지)
//   - 시크릿 .env 는 Jenkins Credentials(secret file, id: dodam-env)로 주입 — 저장소 커밋 금지
//   - 컨트롤러 인-빌드(별도 에이전트 없음)
//
// 흐름: Checkout → [develop만] Secrets Preflight → Build&Test(backend) → [이하 develop만] Docker Build → ai import 스모크 → Deploy → Healthcheck
//   브랜치(MR) 빌드는 테스트까지만 — 자원 절약 + 모든 브랜치가 :local 태그를 덮어쓰는 레이스 방지.
// 알림: 빌드 성공/실패를 Mattermost Incoming Webhook으로 전송 (크레덴셜 id: mattermost-webhook)

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
        deployed = (env.DEPLOY_FROZEN == 'true') ? ' · ⏸️ 배포 프리즈(미배포)' : ' · 🚀 서버 배포됨'
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
  }

  environment {
    COMPOSE_FILE = 'infra/docker-compose.yml'   // 앱 스택 compose (Jenkins 자체 compose와 다름)
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
          echo "브랜치=${env.BRANCH_NAME ?: 'N/A'} · 이미지태그(SHA)=${env.IMAGE_TAG} · 작성자=${env.GIT_AUTHOR}"
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
          '''
        }
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

    stage('Deploy (develop only)') {
      // develop 브랜치에서만 배포 (그 외는 여기까지 = 빌드·테스트만)
      when {
        branch 'develop'
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
            infra/scripts/push-staging-images.sh --tag "$IMAGE_TAG" --with-ai
            infra/scripts/push-staging-images.sh --tag prod         --with-ai

            # 컨테이너 이름은 Deployment 이름과 다를 수 있다 — gateway 의 컨테이너는 nginx 다.
            kubectl -n dodam set image deployment/backend backend=127.0.0.1:5000/dodam-backend:"$IMAGE_TAG"
            kubectl -n dodam set image deployment/gateway nginx=127.0.0.1:5000/dodam-nginx:"$IMAGE_TAG"
            kubectl -n dodam set image deployment/ai      ai=127.0.0.1:5000/dodam-ai:"$IMAGE_TAG"

            # backend 는 replicas 2 + maxUnavailable 0 + preStop 8s 로 무중단이다(362 실증).
            kubectl -n dodam rollout status deployment/backend --timeout=300s
            kubectl -n dodam rollout status deployment/gateway --timeout=300s
            kubectl -n dodam rollout status deployment/ai      --timeout=300s
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
        // ── ① 파드가 실제로 Ready 인가 ────────────────────────────────────────
        // ⚠️ rollout status 만으로는 부족하다 — **replicas 0 인 워크로드에서 즉시 성공**한다.
        //    "롤아웃 성공"과 "떠 있는 파드가 있다"는 다른 말이다(S15P11B209-359 교훈).
        withCredentials([file(credentialsId: 'dodam-kubeconfig', variable: 'DEPLOYER_KUBECONFIG')]) {
          sh '''
            set -e
            export KUBECONFIG="$DEPLOYER_KUBECONFIG"
            fail=0
            for d in backend gateway ai; do
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
        // ── ② 공개 도메인 e2e ────────────────────────────────────────────────
        // 컷오버 전에는 nginx 컨테이너 안에서 127.0.0.1 을 쳤다. 이제는 **사용자가 실제로
        // 지나는 경로**(DNS → 공개 IP → hostPort → gateway 파드 → backend/ai)를 통째로 친다.
        //   ⚠️ NodePort(30080/30443)로 검증하지 않는다. 이 호스트에서는 k3s 가 꺼져 있어도
        //      응답이 오기 때문에 스테이징과 운영을 구분하지 못한다(2026-07-29 실측).
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
          check /                 200 || fail=1
          check /ai/health        200 || fail=1
          check /api/v1/children  401 || fail=1   # 무토큰 차단 = 인증이 살아 있다는 뜻
          check /legal/privacy/   200 || fail=1
          [ "$fail" = "0" ] || { echo "  ✗ 공개 e2e 실패 — 롤백 판단 지점"; exit 1; }
          echo "✅ k3s 배포 정상 + 공개 경로 e2e 통과"
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
