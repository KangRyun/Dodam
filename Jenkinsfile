// 도담 CI/CD 파이프라인 — 단일 EC2 · 레지스트리 없이 로컬 빌드 · develop 배포
// 관련 이슈: S15P11B209-189 (Jenkins CI/CD)
//
// 잡 유형: Multibranch Pipeline 권장(브랜치 자동 감지 → env.BRANCH_NAME 세팅). Deploy는 develop에서만.
// 전제:
//   - Jenkins 컨트롤러에 docker CLI + compose 플러그인 + 호스트 docker.sock (infra/jenkins/ 이미지)
//   - 시크릿 .env 는 Jenkins Credentials(secret file, id: dodam-env)로 주입 — 저장소 커밋 금지
//   - 컨트롤러 인-빌드(별도 에이전트 없음)
//
// 흐름: Checkout → Build&Test(backend) → [이하 develop만] Docker Build → ai import 스모크 → Deploy → Healthcheck
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
      def deployed = (branch == 'develop' && emoji == '✅') ? ' · 🚀 서버 배포됨' : ''
      def text = "${emoji} **${title}** · `${branch}` #${env.BUILD_NUMBER} · ${duration}${deployed}\n" +
                 "👤 ${env.GIT_AUTHOR ?: '?'} · 커밋 `${env.IMAGE_TAG ?: '?'}`"
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
    timeout(time: 30, unit: 'MINUTES') // 무한 매달림 방지
  }

  environment {
    COMPOSE_FILE = 'infra/docker-compose.yml'   // 앱 스택 compose (Jenkins 자체 compose와 다름)
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

    stage('Build & Test — backend') {
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        dir('backend') {
          // 테스트를 여기서 돌린다(이미지 빌드는 -x test로 스킵). 실패 시 파이프라인 중단 = 배포 안 함.
          sh 'chmod +x gradlew && ./gradlew --no-daemon clean test'
        }
      }
      post {
        // 성공/실패 무관하게 테스트 리포트 수집(Jenkins UI에 추이 표시)
        always {
          junit testResults: 'backend/build/test-results/test/*.xml', allowEmptyResults: true
        }
      }
    }

    stage('Docker Build') {
      when { branch 'develop' }      // develop만 이미지 빌드 — 브랜치 빌드가 :local을 덮어 배포 레이스 만드는 것 차단
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 앱 이미지(backend·ai)를 호스트 도커에 바로 빌드(레지스트리 없음). 배포는 :local 사용.
        // 빌드 후 :<SHA> 태그도 부여 → 불변 복원지점(롤백=190에서 이 태그로 되돌림).
        sh '''
          docker compose -f "$COMPOSE_FILE" build
          docker tag dodam-backend:local dodam-backend:${IMAGE_TAG}
          docker tag dodam-ai:local      dodam-ai:${IMAGE_TAG}
          docker tag dodam-nginx:local   dodam-nginx:${IMAGE_TAG}
        '''
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

    stage('Deploy (develop only)') {
      when { branch 'develop' }        // develop 브랜치에서만 배포 (그 외는 여기까지 = 빌드·테스트만)
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 시크릿 .env 를 Credentials(secret file)에서 워크스페이스 밖 임시경로로 주입 → compose up.
        // 같은 호스트라 방금 빌드한 :local 이미지를 그대로 사용(push/pull 불필요).
        // nginx conf 는 이미지에 bake(infra/nginx/Dockerfile) — conf 변경 시 이미지가 바뀌므로
        // up -d 가 컨테이너를 재생성해 자동 반영된다(bind 마운트 경로 사고 방지, 2026-07-22 교훈).
        withCredentials([file(credentialsId: 'dodam-env', variable: 'ENV_FILE')]) {
          sh 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d'
        }
      }
    }

    stage('Healthcheck') {
      when { branch 'develop' }
      steps {
        script { env.CURRENT_STAGE = env.STAGE_NAME }
        // 배포 직후 컨테이너 health가 healthy 될 때까지 대기 — 안 되면 실패로 즉시 인지(190 롤백 트리거 지점).
        sh '''
          set -e
          for svc in dodam-mysql dodam-backend dodam-ai; do
            echo "헬스 대기: $svc"
            ok=false
            for i in $(seq 1 30); do
              status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo missing)
              if [ "$status" = "healthy" ]; then echo "  → $svc healthy"; ok=true; break; fi
              sleep 5
            done
            if [ "$ok" != "true" ]; then echo "  ✗ $svc 헬스체크 실패(마지막 상태: $status)"; exit 1; fi
          done
          # 게이트웨이 e2e — 컨테이너 health만으론 nginx 라우팅 고장(빈 conf 등)을 못 잡는다(2026-07-22 사고).
          # nginx 안에서 자기 자신을 거쳐 ai까지: 외부 진입 경로 전체를 실검증.
          # ⚠️ 주소는 반드시 127.0.0.1 — 컨테이너 안 'localhost'는 ::1(IPv6)로 먼저 풀리는데
          #    우리 nginx는 IPv4(0.0.0.0:80)만 리슨하고 busybox wget은 IPv4 폴백이 없어
          #    항상 refused 난다(이걸로 오탐 2회: 처음엔 기동 레이스로 오진했음).
          #    재시도 루프는 기동 직후 리슨 대기용으로 유지. 에러 출력은 숨기지 않는다(진단 가능하게).
          echo "게이트웨이 e2e 확인: nginx → /ai/health"
          ok=false
          for i in $(seq 1 10); do
            if docker exec dodam-nginx wget -q -O /dev/null -T 5 http://127.0.0.1/ai/health; then ok=true; break; fi
            sleep 2
          done
          if [ "$ok" != "true" ]; then echo "  ✗ 게이트웨이 e2e 실패(재시도 소진)"; exit 1; fi
          echo "✅ 전체 서비스 healthy + 게이트웨이 라우팅 정상"
        '''
      }
    }
  }

  post {
    success {
      echo "✅ 파이프라인 성공 (배포 이미지 태그=${env.IMAGE_TAG})"
      script { notifyMattermost('✅', '빌드 성공') }
    }
    failure {
      echo "❌ 실패 — 미배포이거나 헬스체크 실패. 콘솔 로그 확인 후 대응."
      script { notifyMattermost('❌', '빌드 실패') }
    }
    always  { sh 'docker image prune -f >/dev/null 2>&1 || true' }  // 대롱거리는 중간 이미지 정리(디스크 절약)
  }
}
