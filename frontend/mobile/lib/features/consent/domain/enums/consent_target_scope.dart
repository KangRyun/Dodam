/// 동의 약관의 적용 범위. 보호자 본인([user])과 아동 대상([child])을 구분한다.
///
/// `GET /consents/terms`의 `targetScope` Query와 응답 필드에 같은 값이 쓰인다
/// (계약 정본 §9.2). 서버는 Query를 생략하면 전 범위를 돌려준다.
enum ConsentTargetScope {
  user('USER'),
  child('CHILD');

  const ConsentTargetScope(this.wire);

  /// 서버 Query·응답에 쓰는 값.
  final String wire;

  /// 서버가 내려준 값에 대응하는 범위. 비어 있거나 모르는 값이면 `null`.
  ///
  /// 서버가 범위를 늘려도 목록 조회가 통째로 실패하지 않도록 예외 대신 `null`을
  /// 돌려준다. 화면은 범위를 모르는 약관도 감추지 않고 마지막에 모아 보여준다.
  static ConsentTargetScope? fromWire(Object? value) {
    for (final scope in values) {
      if (scope.wire == value) return scope;
    }
    return null;
  }
}
