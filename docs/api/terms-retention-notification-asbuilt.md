# 약관 변경·보관 만료 알림 as-built (S15P11B209-557)

> Jira: `S15P11B209-557`([BE][P0] 약관 변경·보관 만료 알림 이벤트 처리)
> 지배 계약: `docs/api/push-notification-delivery-contract.md`(발송 페이로드·규약 §0·§3·§5·§6) — 이 문서는 그 계약을 **소비**하며 발송 규약을 다시 서술하지 않는다.
> 선행 계약: `docs/api/notification-inbox-contract.md`(알림함·Token)
> 최종 수정: 2026-07-29

557은 알림 어휘 `CONSENT_UPDATED`(약관 변경)·`RETENTION_NOTICE`(보관 만료) 두 종의 **트리거·수신자 선정·알림함 원본 생성**을 신설하고, 발송은 556이 만든 범용 하류(`NotificationPushDispatcher` → `PushSender`)를 무수정 재사용한다. 이슈 본문·댓글에 트리거 시점·수신자·문구 정의가 없어 아래를 as-built로 확정한다. 명세서 `API_명세서_최종.md`는 두 type의 어휘만 정의하고 트리거를 정의하지 않으므로, 명세 보강은 문서 담당자 몫으로 남긴다.

## 1. 신규 어휘·마이그레이션

- 알림 type `CONSENT_UPDATED`·`RETENTION_NOTICE`는 이미 `NotificationTypes`와 `notifications.notification_type` CHECK(V1)에 존재한다. **신규 type·신규 컬럼·신규 마이그레이션 없음.**
- 두 알림 모두 연결 자원이 없어 페이로드에 `relatedResourceType`·`relatedResourceId`를 넣지 않는다(계약 §3과 일치, 알림함 행의 관련 자원 세 컬럼도 모두 `null`).

## 2. 556 재사용 범위

| 재사용(무수정) | 미러링만(재사용 안 함) |
| --- | --- |
| `NotificationPushDispatcher`(범용 dispatch), `NotificationDeliveryService`, `CreatedNotification`, `Notification.create(...)`, `PushSender`/`PushMessage`/`PushSendOutcome`, `infrastructure/push/*` | 556 전용 `AnalysisCompletedNotificationService`·`AnalysisCompletedPushListener`·`AnalysisCompletedRecipientRepository`(패턴만 참고) |

생성(트랜잭션)과 발송(부수효과)을 분리하는 556 패턴을 그대로 따른다. 알림함 행을 먼저 커밋한 뒤 발송하며, 발송 실패는 삼켜 생성·상위 처리를 롤백하지 않는다(계약 §0-6·§0-7).

## 3. 약관 변경 → `CONSENT_UPDATED`

### 트리거 진입점 (호출부는 미존)
- 진입점: `TermsChangeNotifier.notifyTermsUpdated(String termCode, String newVersion)`.
- **실제 호출부는 아직 없다.** 약관 새 버전을 게시·시행하는 관리 기능이 리포에 없다(`ConsentTerm.define`은 테스트·향후용). 이 진입점은 향후 약관 관리 기능이 새 `ConsentTerm`을 시행할 때 호출하도록 배선할 **명시적 서비스 훅**으로 제공한다. 인증 없는 공개/관리 REST 엔드포인트나 관리 CRUD는 만들지 않았다(158 죽은코드 교훈: 임의 관리 기능 선구현 금지). 실제 호출부는 약관 관리 기능(미존) 소유.
- `newVersion`은 트리거 맥락 로깅에만 쓰고 알림 본문에는 담지 않는다(계약 §6 중립 문구).

### 수신자 선정 (기본값 채택, 근거)
- 명세·계약에 수신자 정의가 없어 **"변경된 약관 코드에 현재 활성 동의를 보유한 사용자"**(재동의 필요 대상)를 기본값으로 채택.
- 경로: `TermsChangeRecipientRepository.findActiveConsentUserIdsByTermCode(termCode)`
  (`TermsChangeRecipientRepository.java:findActiveConsentUserIdsByTermCode`).
- append-only `consent_records`에서 약관 코드(`consent_terms.term_code`)의 **버전·대상별 마지막 행위가 `AGREE`**인 사용자를 중복 없이 반환한다. 사용자 본인 약관(`subject_child_id is null`)과 아동 약관을 모두 포함하고, 아동 약관의 재동의 주체도 보호자이므로 수신자는 `actor_user_id`(보호자 사용자)로 통일한다. `ConsentStatusRepository`의 "약관별 최신 행위" 판정과 동일한 방식이다.
- 문구: `title="약관이 변경되었어요"`, `content="변경된 약관을 확인해 주세요"`(중립, 어떤 약관·무엇이 바뀌었는지 미포함).

## 4. 보관 만료 → `RETENTION_NOTICE`

### 트리거
- `@Scheduled` 배치 `RetentionNoticeScheduler.notifyExpiringRetention()`(`SttPendingRecoveryScheduler` 패턴). 주기 `app.notification.retention.interval`(기본 `1h`).

### 만료 기준 소스 (실재 컬럼 없음 → 임시 기준 + enabled 게이트)
- **전용 보관·만료·삭제예정 컬럼이 스키마에 없다.** 보관 정책·수치·스케줄러가 전무(564/565 미완). `children.deleted_at`은 소프트 삭제 시각(이미 삭제)이고, 그 외 `expires_at`류는 토큰·세션·HTP 재개·다운로드 만료로 데이터 보관과 무관.
- **가정(임시):** 소프트 삭제된 아동 데이터는 `retention-days`(기본 180) 뒤 영구 삭제된다고 보고, 그 만료 `notice-days-before`(기본 30)일 전에 보호자에게 안내한다.
  - 만료 임박 기준일 `cutoff = now - retentionDays + noticeDaysBefore`. `children.deleted_at <= cutoff`(삭제됨)인 아동의 보호자를 대상으로 한다.
  - 경로: `RetentionExpiryRepository.findExpiringDataOwnerUserIds(cutoff, batchSize)` — `children` × `guardian_child_relations`로 보호자 `guardian_user_id`를 중복 없이 조회.
- **`app.notification.retention.enabled` 기본 `false`.** 꺼져 있으면 조회·생성·발송 어느 것도 하지 않는다(가짜 기준일로 오발송 방지 게이트). **보관 정책(564/565) 확정 전까지 enabled=false, 기준일 임시.** 확정되면 실제 만료 시각과 재알림 억제를 그 도메인이 소유한다.
- **알려진 한계:** 매 실행마다 대상을 재조회하므로 enabled=true로 켜면 같은 보호자에게 반복 발송될 수 있다. 재알림 억제(notified 상태)는 보관 정책 도메인(564/565)이 소유할 몫이라 이번 범위에서 새 컬럼/마이그레이션을 추가하지 않았다. enabled=false 기본이므로 현재는 미발송.
- 문구: `title="보관 기간이 곧 만료돼요"`, `content="보관 기간이 만료되기 전에 확인해 주세요"`(중립, 아동·데이터 정보 미포함).

## 5. 설정 (application.yml `app.notification.retention`)

| 키 | 기본값 | 설명 |
| --- | --- | --- |
| `enabled` | `false` | 보관 만료 임박 알림 발송 스위치. 정책 확정 전까지 false |
| `interval` | `1h` | 스케줄러 실행 주기(fixedDelay) |
| `retention-days` | `180` | 보관 기간(일). 임시 기준값 |
| `notice-days-before` | `30` | 만료 며칠 전 안내 |
| `batch-size` | `100` | 한 실행에서 처리할 최대 대상 수 |

발송 스위치 `app.push.fcm.enabled`(556)는 별개다. `false`면 알림함 행은 생성되고 FCM 발송만 조용히 생략된다(계약 §0-6).

## 6. 신규 파일

- `notification/service/TermsChangeNotifier.java`, `TermsChangeNotificationService.java`, `notification/repository/TermsChangeRecipientRepository.java`
- `notification/service/RetentionNoticeScheduler.java`, `RetentionNoticeNotificationService.java`, `RetentionNoticeProperties.java`, `notification/repository/RetentionExpiryRepository.java`
