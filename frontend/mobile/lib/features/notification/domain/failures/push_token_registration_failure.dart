/// 디바이스 Token 등록(NOTI-01)이 서버 정책에 막힌 이유.
///
/// 네트워크 오류처럼 다시 시도하면 풀릴 수 있는 실패는 여기에 넣지 않는다.
/// 이 열거값은 "다시 시도해도 지금 계정은 푸시를 받지 못한다"에 해당하는
/// 응답만 담는다(`docs/api/notification-inbox-contract.md` §4 오류 표).
enum PushTokenRegistrationFailureType {
  /// 409 `DEVICE_TOKEN_ALREADY_REGISTERED` — 같은 Token이 다른 계정에 등록돼 있다.
  ///
  /// 한 기기를 여러 계정으로 로그인하면 생긴다. Token 소유권은 서버가 정하며
  /// (S15P11B209-549/550) 앱은 강제 재등록을 시도하지 않는다.
  claimedByAnotherAccount,

  /// 503 `DEVICE_TOKEN_STORAGE_UNAVAILABLE` — 서버 Token 암호화 키가 없다.
  ///
  /// 서버는 평문 저장으로 후퇴하지 않고 등록 API만 거부한다(계약 §2).
  storageUnavailable,
}

/// 디바이스 Token 등록이 계약된 이유로 거절됐음을 나타낸다.
///
/// 등록에 실패하면 이 기기·이 계정은 푸시를 받지 못하므로, 조용히 삼키면 알림
/// 배지가 "눌러야 올라가는" 상태로 남는다. 상위 계층이 보호자에게 알릴 수 있게
/// 실패 이유를 타입으로 노출한다.
final class PushTokenRegistrationFailure implements Exception {
  const PushTokenRegistrationFailure({
    required this.type,
    this.code,
    this.cause,
  });

  final PushTokenRegistrationFailureType type;

  /// 서버가 준 오류 코드. 로그·진단용이며 화면 분기에는 [type]을 쓴다.
  final String? code;
  final Object? cause;

  @override
  String toString() =>
      'PushTokenRegistrationFailure(type: ${type.name}, code: $code)';
}
