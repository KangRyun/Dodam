// 도담 CI/CD 파이프라인 — 단일 EC2 · 레지스트리 없이 로컬 빌드 · develop 배포
// 관련 이슈: S15P11B209-189 (Jenkins CI/CD)
//
// 잡 유형: Multibranch Pipeline 권장(브랜치 자동 감지 → env.BRANCH_NAME 세팅). Deploy는 develop에서만.
// 전제:
//   - Jenkins 컨트롤러에 docker CLI + compose 플러그인 + 호스트 docker.sock (infra/jenkins/ 이미지)
//   - 시크릿 .env 는 Jenkins Credentials(secret file, id: dodam-env)로 주입 — 저장소 커밋 금지
//   - 컨트롤러 인-빌드(별도 에이전트 없음)
//
// 흐름: Checkout → Build&Test(backend) → Docker Build → ai import 스모크 → Deploy(develop) → Healthcheck
// 알림: 빌드 성공/실패를 Mattermost Incoming Webhook으로 전송 (크레덴셜 id: mattermost-webhook)

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
      steps {
        // 앱 이미지(backend·ai)를 호스트 도커에 바로 빌드(레지스트리 없음). 배포는 :local 사용.
        // 빌드 후 :<SHA> 태그도 부여 → 불변 복원지점(롤백=190에서 이 태그로 되돌림).
        sh '''
          docker compose -f "$COMPOSE_FILE" build
          docker tag dodam-backend:local dodam-backend:${IMAGE_TAG}
          docker tag dodam-ai:local      dodam-ai:${IMAGE_TAG}
        '''
      }
    }

    stage('Test — ai (import smoke)') {
      steps {
        // ai는 아직 유닛테스트 없음 → 빌드된 이미지에서 앱이 import 되는지만 확인. (TODO: 실제 테스트 추가)
        sh 'docker run --rm dodam-ai:local python -c "import main; print(\'ai import OK\')"'
      }
    }

    stage('Deploy (develop only)') {
      when { branch 'develop' }        // develop 브랜치에서만 배포 (그 외는 여기까지 = 빌드·테스트만)
      steps {
        // 시크릿 .env 를 Credentials(secret file)에서 워크스페이스 밖 임시경로로 주입 → compose up.
        // 같은 호스트라 방금 빌드한 :local 이미지를 그대로 사용(push/pull 불필요).
        withCredentials([file(credentialsId: 'dodam-env', variable: 'ENV_FILE')]) {
          sh 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d'
        }
      }
    }

    stage('Healthcheck') {
      when { branch 'develop' }
      steps {
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
          echo "✅ 전체 서비스 healthy"
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
