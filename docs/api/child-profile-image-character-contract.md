# 아동 프로필 이미지·캐릭터 계약

## 1. 목적과 범위

아동 프로필에는 보호자가 업로드한 사진과 앱에 포함된 캐릭터 중 하나를 표시할 수 있다. Backend는 업로드 파일의 소유권과 연결 상태, 선택한 캐릭터 코드를 저장한다. 캐릭터 이미지 파일은 Flutter bundle asset으로 관리한다.

표시 우선순위는 다음과 같다.

1. `profileImageUrl`이 있으면 업로드 사진을 표시한다.
2. 사진이 없고 `preferredCharacter`가 있으면 해당 캐릭터 asset을 표시한다.
3. 두 값이 모두 없으면 기본 도담이 캐릭터를 표시한다.

## 2. 프로필 이미지 사전 업로드

### Request

```http
POST /api/v1/child-profile-images
Authorization: Bearer {accessToken}
Content-Type: multipart/form-data
```

| Part | 형식 | 필수 | 설명 |
| --- | --- | --- | --- |
| `image` | binary | O | PNG 또는 JPEG 이미지 |

검증 정책:

- 실제 파일 Signature가 PNG 또는 JPEG여야 한다.
- 파일 크기는 5 MiB(5,242,880 bytes) 이하여야 한다.
- 공통 이미지 차원 정책을 충족해야 한다.
- 원본 파일명이나 요청 `Content-Type`만 신뢰하지 않는다.

### Response

```json
{
  "success": true,
  "code": "COMMON_201_001",
  "message": "요청이 성공했습니다.",
  "data": {
    "profileImageFileId": "d20f42a9-6a55-4c91-b4b0-b6c79b8bd121",
    "contentType": "image/png",
    "fileSizeBytes": 1048576,
    "widthPx": 512,
    "heightPx": 512,
    "expiresAt": "2026-08-01T00:00:00Z"
  }
}
```

업로드 직후 파일은 `TEMP` 상태이며 24시간 안에 아동과 연결해야 한다. `storageKey`는 외부에 노출하지 않는다.

## 3. 아동 등록·수정 연결 계약

### 아동 등록

`POST /api/v1/children`의 `profileImageFileId`는 선택값이다.

- 생략 또는 `null`: 사진 없이 아동을 등록한다.
- UUID 전달: 현재 보호자가 업로드한 유효한 `TEMP` 파일을 새 아동과 연결한다.
- 존재하지 않거나 만료되거나 이미 연결되었거나 다른 사용자가 업로드한 파일은 거부한다.

### 아동 수정

`PATCH /api/v1/children/{childId}`는 JSON 필드 존재 여부를 구분한다.

- `profileImageFileId` 생략: 기존 사진을 유지한다.
- `profileImageFileId: null`: 기존 사진 연결을 해제하고 Storage 삭제 큐에 등록한다.
- 다른 UUID 전달: 기존 사진을 교체하고 새 파일을 연결한다.

목록·상세·등록·수정 응답의 `profileImageUrl`은 JWT 인증이 필요한 Backend proxy URL이다. MinIO 내부 주소, `storageKey`, presigned URL은 반환하지 않는다.

## 4. 캐릭터 코드 계약

`preferredCharacter`의 허용값은 다음 일곱 가지다.

| 코드 | 표시명 | Flutter asset |
| --- | --- | --- |
| `BASE` | 도담이 | `assets/characters/costumes/dodam_base.png` |
| `PRINCESS` | 공주 도담이 | `assets/characters/costumes/dodam_princess.png` |
| `DINO` | 공룡 도담이 | `assets/characters/costumes/dodam_dino.png` |
| `OCTOPUS` | 문어 도담이 | `assets/characters/costumes/dodam_octopus.png` |
| `EXPLORER` | 탐험가 도담이 | `assets/characters/costumes/dodami_explorer_profile.png` |
| `RIBBON` | 리본 도담이 | `assets/characters/costumes/dodami_ribbon_profile.png` |
| `PRINCE` | 왕자 도담이 | `assets/characters/costumes/dodami_prince_profile.png` |

`EXPLORER`·`RIBBON`·`PRINCE`는 `S15P11B209-866`에서 추가했다. 코드는 캐릭터 외형만 가리키며 성별·연령·진단 의미를 갖지 않는다.

`POST /api/v1/children`에서는 생략 또는 `null`을 허용한다. `PATCH /api/v1/children/{childId}`에서는 필드 생략 시 기존 값을 유지하고 명시적 `null`이면 선택을 해제한다. 허용 목록 밖의 문자열은 HTTP 400으로 거부한다.

## 5. 파일 수명주기와 보안

- 파일 식별자는 추측하기 어려운 UUID 문자열이다.
- 업로드 사용자와 연결을 요청한 보호자가 같아야 한다.
- 연결된 아동에 접근 가능한 보호자만 이미지 Byte를 조회할 수 있다.
- 교체·삭제 파일은 DB Transaction에서 삭제 큐에 등록하고 실제 Storage 삭제는 재시도 가능한 작업으로 처리한다.
- 연결되지 않은 `TEMP` 파일은 `expiresAt` 이후 수명주기 작업에서 삭제한다.
- API 응답과 로그에는 아동 이미지 Byte, 원본 파일명, `storageKey`를 남기지 않는다.

## 6. 관련 Jira

- `S15P11B209-755`: 프로필 이미지 업로드 API
- `S15P11B209-756`: 아동 등록·수정 이미지 연결 및 조회
- `S15P11B209-757`: 캐릭터 코드·표시 우선순위
- `S15P11B209-866`: 캐릭터 선택 캐러셀 신규 도담이 3종 추가
