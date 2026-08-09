import 'package:dodam/core/domain/report_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('옛 실패와 최종 실패는 보호자에게 실패로 보인다', () {
    // 회귀: 실패가 셋으로 갈라진 뒤에도 화면들이 'FAILED' 하나만 알고 있어서,
    //   FAILED_FINAL 로 끝난 리포트가 보호자에게 영원히 "분석 중"으로 남았다.
    expect(isReportFailureVisibleToGuardian('FAILED'), isTrue);
    expect(isReportFailureVisibleToGuardian('FAILED_FINAL'), isTrue);
  });

  test('재시도 대기 중인 실패는 실패로 보이지 않는다', () {
    // 재시도 작업이 아직 집어 갈 수 있어 보호자가 지금 할 일이 없다.
    expect(isReportFailureVisibleToGuardian('FAILED_RETRYABLE'), isFalse);
    expect(isReportRetryableFailure('FAILED_RETRYABLE'), isTrue);
  });

  test('진행 중과 완료, 모르는 값은 실패가 아니다', () {
    expect(isReportFailureVisibleToGuardian('GENERATING'), isFalse);
    expect(isReportFailureVisibleToGuardian('COMPLETED'), isFalse);
    expect(isReportFailureVisibleToGuardian(null), isFalse);
    expect(isReportFailureVisibleToGuardian('WHATEVER'), isFalse);
  });
}
