import 'api_failure.dart';

/// 사용자에게 보여줄 실패 원인 분류.
///
/// [ApiFailure]는 "HTTP 응답을 받았는가"까지만 구분한다. 화면은 그보다
/// 한 단계 더 나아가 "연결 문제인가 / 서버 문제인가 / 다시 시도해서
/// 해결될 문제인가"를 알아야 안내 문구와 재시도 버튼을 정할 수 있다.
enum ApiFailureKind {
  /// 기기가 서버에 닿지 못함(비행기 모드·Wi-Fi 끊김 등).
  offline,

  /// 연결은 됐으나 응답이 제한 시간 안에 오지 않음.
  timeout,

  /// 서버가 5xx로 응답.
  server,

  /// 401 — 재발급까지 실패한 세션 만료.
  unauthorized,

  /// 403 — 권한 없음.
  forbidden,

  /// 404 — 대상 없음.
  notFound,

  /// 그 밖의 4xx — 요청 자체가 잘못됨.
  client,

  /// 화면 이탈 등으로 요청이 취소됨.
  cancelled,

  /// 분류할 수 없는 실패.
  unknown;

  /// 연결 계열인지 여부. 화면은 이 값으로 `AppRetryView`(연결 안내)와
  /// `AppErrorView`(일반 오류) 중 무엇을 보여줄지 정한다.
  bool get isConnectivity =>
      this == ApiFailureKind.offline || this == ApiFailureKind.timeout;
}

/// 실패 객체를 화면 문구·재시도 가능 여부로 변환한 결과.
///
/// 제목은 화면마다 다르므로(무엇을 못 불러왔는지) 여기서 만들지 않는다.
/// 화면이 가진 도메인 제목 + 여기서 정한 원인 문구를 조합해 쓴다.
final class ApiFailurePresentation {
  const ApiFailurePresentation({
    required this.kind,
    required this.message,
    required this.canRetry,
  });

  /// 임의의 실패 객체를 표현으로 변환한다.
  ///
  /// [failure]는 [ApiFailure]가 아닐 수도 있다(파싱 오류 등). 그 경우
  /// [ApiFailureKind.unknown]으로 떨어뜨려 화면이 항상 무언가는 보여주게 한다.
  ///
  /// [childFriendly]가 참이면 원인을 드러내지 않는 쉬운 말만 쓴다.
  /// 아동 화면에는 오류 상세를 노출하지 않는다(CLAUDE.md 9절 가드레일).
  factory ApiFailurePresentation.of(
    Object? failure, {
    bool childFriendly = false,
  }) {
    final kind = _kindOf(failure);
    return ApiFailurePresentation(
      kind: kind,
      message: childFriendly ? _childMessage(kind) : _guardianMessage(kind),
      canRetry: _canRetry(kind),
    );
  }

  final ApiFailureKind kind;
  final String message;

  /// 다시 시도해서 상황이 달라질 수 있는지. 거짓이면 재시도 버튼을 감춘다.
  ///
  /// 401·403·404·4xx는 같은 요청을 반복해도 결과가 같다. 재시도 버튼을
  /// 남겨두면 사용자가 무의미한 재요청을 반복하게 된다.
  final bool canRetry;

  bool get isConnectivity => kind.isConnectivity;

  static ApiFailureKind _kindOf(Object? failure) => switch (failure) {
    ApiTransportFailure(:final type) => switch (type) {
      ApiTransportFailureType.connection => ApiFailureKind.offline,
      ApiTransportFailureType.connectionTimeout ||
      ApiTransportFailureType.sendTimeout ||
      ApiTransportFailureType.receiveTimeout ||
      ApiTransportFailureType.transformTimeout => ApiFailureKind.timeout,
      ApiTransportFailureType.cancelled => ApiFailureKind.cancelled,
      ApiTransportFailureType.unknown => ApiFailureKind.unknown,
    },
    ApiResponseFailure(:final statusCode) => _kindOfStatus(statusCode),
    _ => ApiFailureKind.unknown,
  };

  static ApiFailureKind _kindOfStatus(int? statusCode) {
    if (statusCode == null) return ApiFailureKind.unknown;
    if (statusCode >= 500) return ApiFailureKind.server;
    return switch (statusCode) {
      401 => ApiFailureKind.unauthorized,
      403 => ApiFailureKind.forbidden,
      404 => ApiFailureKind.notFound,
      >= 400 => ApiFailureKind.client,
      _ => ApiFailureKind.unknown,
    };
  }

  static bool _canRetry(ApiFailureKind kind) => switch (kind) {
    ApiFailureKind.offline ||
    ApiFailureKind.timeout ||
    ApiFailureKind.server ||
    ApiFailureKind.unknown => true,
    ApiFailureKind.unauthorized ||
    ApiFailureKind.forbidden ||
    ApiFailureKind.notFound ||
    ApiFailureKind.client ||
    ApiFailureKind.cancelled => false,
  };

  static String _guardianMessage(ApiFailureKind kind) => switch (kind) {
    ApiFailureKind.offline => '인터넷 연결이 끊겼어요. 연결 상태를 확인하고 다시 시도해 주세요.',
    ApiFailureKind.timeout => '응답이 늦어지고 있어요. 잠시 후 다시 시도해 주세요.',
    ApiFailureKind.server => '서비스에 일시적인 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
    ApiFailureKind.unauthorized => '로그인이 만료됐어요. 다시 로그인해 주세요.',
    ApiFailureKind.forbidden => '이 정보를 볼 수 있는 권한이 없어요.',
    ApiFailureKind.notFound => '찾으시는 정보가 없어요.',
    ApiFailureKind.client => '요청을 처리하지 못했어요. 입력한 내용을 확인해 주세요.',
    ApiFailureKind.cancelled => '요청이 취소됐어요.',
    ApiFailureKind.unknown => '알 수 없는 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
  };

  /// 아동용 문구는 두 가지뿐이다 — 원인을 알려주는 것이 목적이 아니라
  /// 아이가 놀라지 않고 다시 시도하게 하는 것이 목적이다.
  static String _childMessage(ApiFailureKind kind) => kind.isConnectivity
      ? '연결이 잠깐 끊겼어요. 다시 해볼까요?'
      : '지금은 잘 안 돼요. 조금 뒤에 다시 해볼까요?';
}
