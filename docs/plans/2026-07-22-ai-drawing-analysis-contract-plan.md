# AI 그림 분석 요청·응답 계약 구현 계획

> Jira: `S15P11B209-144`

## 1. 계약 테스트 RED

- `backend/src/test/java/com/ssafy/b209/analysis/dto/DrawingAnalysisContractTest.java`를 추가한다.
- 요청·성공·빈 탐지·실패 JSON round-trip, Enum 문자열, 필수값, confidence 경계, Bounding Box, 알 수 없는 Enum, Entity 미포함을 검증한다.
- 테스트를 단독 실행해 아직 타입이 없어 실패하는 것을 확인한다.

## 2. 요청 계약 GREEN

- `DrawingAnalysisRequest`, `DrawingImageReference`, `DrawingAnalysisType`을 추가한다.
- Bean Validation으로 ID, 문자열, MIME Type, 안전한 `storageKey`를 검증한다.

## 3. 응답 계약 GREEN

- `DrawingAnalysisResponse`, `DrawingAnalysisModelResponse`, `DrawingDetectionResponse`, `BoundingBoxResponse`, `DrawingAnalysisErrorResponse`, `DrawingAnalysisStatus`를 추가한다.
- 값 범위와 상태별 payload 일관성을 검증하고 목록을 방어적으로 복사한다.
- 모든 공개 Production Type에 실제 책임 중심의 한국어 Javadoc을 작성한다.

## 4. 계약 문서

- `docs/api/ai-drawing-analysis-contract.md`에 요청·성공·실패 JSON, 필드, Enum, 범위, 제한 및 후속 이슈를 기록한다.

## 5. 검증

- `gradlew.bat clean test`
- `gradlew.bat spotlessCheck`
- `gradlew.bat javadoc`
- 변경 범위, Entity/Client/Controller/DB 미포함, Git 상태를 확인한다.
- Commit과 push는 수행하지 않고 권장 메시지만 보고한다.
