# S15P11B209

아동의 그림과 대화를 기반으로 정서 표현을 돕고, 보호자와 전문가에게 활동 기록을 제공하는 서비스입니다.

## Repository structure

```text
S15P11B209/
├── frontend/
│   ├── mobile/        # Flutter 앱
│   └── web/           # Next.js 웹
├── backend/           # Spring Boot API 서버
├── ai/                # AI 추론 및 학습
├── infra/             # Docker, Nginx, 배포 설정
├── docs/              # API 명세, ERD, 개발 문서
├── .env.example
├── .editorconfig
├── .gitattributes
└── .gitignore
```

## Initial setup

1. `.env.example`을 복사하여 `.env`를 만듭니다.
2. 실제 비밀번호, API 키, 모델 파일 및 데이터셋은 Git에 올리지 않습니다.
3. 기능 개발은 `feature/기능명` 브랜치에서 진행합니다.

## Branch convention

- `master`: 배포 및 최종 통합 브랜치
- `develop`: 개발 통합 브랜치
- `feature/*`: 기능 개발 브랜치
- `fix/*`: 버그 수정 브랜치

## Commit convention

- `feat`: 기능 추가
- `fix`: 버그 수정
- `docs`: 문서 변경
- `refactor`: 코드 구조 개선
- `test`: 테스트 추가 및 변경
- `chore`: 설정 및 빌드 작업

