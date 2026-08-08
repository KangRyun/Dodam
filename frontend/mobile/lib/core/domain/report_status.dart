/// 서버가 내려주는 리포트 상태 문자열을 화면이 같은 기준으로 읽게 한다.
///
/// 리포트 실패가 하나였다가 셋으로 갈라졌다(S15P11B209-1016).
///
///     FAILED_RETRYABLE   다시 부르면 될 수 있는 실패. 재시도 작업이 스스로 집어 간다.
///     FAILED_FINAL       몇 번을 더 불러도 같은 자리에서 멈추는 실패.
///     FAILED             그 구분이 생기기 전에 쌓인 옛 실패.
///
/// 이 갈래가 생긴 뒤에도 화면들은 `'FAILED'` 하나만 알고 있어서, 새 이름으로 실패한
/// 리포트가 전부 기본 분기로 빠져 **보호자에게 영원히 "분석 중"으로 남았다**. 상태 문자열을
/// 화면마다 따로 비교하면 다음에 이름이 하나 더 늘 때 같은 일이 또 일어난다.
library;

/// 보호자에게 실패로 보여야 하는 상태인가.
///
/// `FAILED_RETRYABLE` 은 **일부러 제외한다.** 재시도 작업이 아직 집어 갈 수 있는 상태라
/// 보호자가 지금 할 수 있는 일이 없고, 곧 성공할 수도 있는 리포트에 "다시 확인 필요"를
/// 붙이면 없는 문제를 만든다. 그동안에는 진행 중으로 보이는 편이 사실에 가깝다.
bool isReportFailureVisibleToGuardian(String? reportStatus) =>
    reportStatus == 'FAILED' || reportStatus == 'FAILED_FINAL';

/// 재시도 작업이 아직 집어 갈 수 있는, 진행 중으로 보여야 하는 실패인가.
bool isReportRetryableFailure(String? reportStatus) =>
    reportStatus == 'FAILED_RETRYABLE';
