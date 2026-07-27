#!/usr/bin/env python3
"""FCM HTTP v1으로 계약 형식(data-only) 테스트 푸시를 보낸다.

Firebase 콘솔의 '테스트 메시지'는 notification 페이로드를 실어 보내서
앱이 파싱하는 data-only 계약(docs/api/push-notification-delivery-contract.md §3)과
맞지 않는다. 실기기 검증에는 이 스크립트를 쓴다.

사용:
    pip install google-auth requests
    python3 infra/scripts/send-test-push.py \\
        --credentials /path/to/fcm-service-account.json \\
        --token <기기 FCM 등록 Token>

옵션으로 알림 유형·연결 자원을 바꿔 라우팅까지 확인할 수 있다.

⚠️ Service Account JSON은 개인키를 담고 있다. 저장소에 커밋하지 말고
   경로만 넘긴다(infra/secrets/ 는 .gitignore 대상).
"""

import argparse
import json
import sys

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# 계약 §3이 허용하는 알림 유형
ALLOWED_TYPES = (
    "ANALYSIS_COMPLETED",
    "ANALYSIS_FAILED",
    "REPORT_COMPLETED",
    "NEW_EXPERT_POST",
    "COMMENT_CREATED",
    "CONSENT_UPDATED",
    "RETENTION_NOTICE",
    "ACTIVITY_REMINDER",
    "RISK_REVIEW_GUIDE",
)
ALLOWED_RESOURCES = ("REPORT", "DRAWING_SESSION", "POST")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials", required=True, help="Service Account JSON 경로")
    parser.add_argument("--token", required=True, help="기기 FCM 등록 Token")
    parser.add_argument("--notification-id", default="900")
    parser.add_argument("--type", default="ANALYSIS_COMPLETED", choices=ALLOWED_TYPES)
    parser.add_argument("--title", default="분석이 완료됐어요")
    parser.add_argument("--content", default="리포트를 확인해 보세요")
    parser.add_argument("--resource-type", choices=ALLOWED_RESOURCES)
    parser.add_argument("--resource-id")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="발송하지 않고 페이로드만 출력한다",
    )
    return parser.parse_args()


def build_data(args: argparse.Namespace) -> dict[str, str]:
    """계약 §3 페이로드를 만든다. 모든 값은 문자열이어야 한다."""
    data = {
        "notificationId": args.notification_id,
        "type": args.type,
        "title": args.title,
        "content": args.content,
    }
    # 자원 유형과 식별자는 쌍이다. 한쪽만 있으면 앱이 둘 다 버린다(계약 §3).
    if bool(args.resource_type) != bool(args.resource_id):
        sys.exit("자원 유형과 식별자는 함께 지정해야 한다 (--resource-type/--resource-id)")
    if args.resource_type:
        data["relatedResourceType"] = args.resource_type
        data["relatedResourceId"] = args.resource_id
    return data


def main() -> None:
    args = parse_args()
    data = build_data(args)

    # notification 블록을 넣지 않는다 — 넣으면 OS가 자동 표시해 앱이 아동 모드
    # 차단·중복 방지·라우팅을 제어할 수 없다(계약 §0-1).
    message = {
        "message": {
            "token": args.token,
            "data": data,
            # data-only는 기본 우선순위에서 지연될 수 있어 높인다.
            "android": {"priority": "high"},
        }
    }

    if args.dry_run:
        print(json.dumps(message, ensure_ascii=False, indent=2))
        return

    try:
        import requests
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError:
        sys.exit("의존성이 없다. 먼저 실행: pip install google-auth requests")

    credentials = service_account.Credentials.from_service_account_file(
        args.credentials, scopes=[FCM_SCOPE]
    )
    credentials.refresh(Request())

    with open(args.credentials, encoding="utf-8") as file:
        project_id = json.load(file)["project_id"]

    response = requests.post(
        FCM_ENDPOINT.format(project_id=project_id),
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json; UTF-8",
        },
        json=message,
        timeout=15,
    )

    print(f"HTTP {response.status_code}")
    print(response.text)
    if response.status_code != 200:
        # UNREGISTERED/INVALID_ARGUMENT면 해당 Token은 죽은 것이다(계약 §5.3).
        sys.exit(1)


if __name__ == "__main__":
    main()
