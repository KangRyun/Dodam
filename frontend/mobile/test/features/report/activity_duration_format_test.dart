import 'package:dodam/features/report/presentation/format/activity_duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// 활동 시간 문구의 경계값을 고정한다(S15P11B209-859).
///
/// 실기기 검증에서 18.3초 활동이 `0분` 으로 표시됐다. 분만 반올림해서 보여준
/// 탓인데, 같은 실수가 다시 들어오지 않도록 경계마다 기대 문구를 못 박는다.
void main() {
  group('formatActivityDuration', () {
    test('값이 없으면 표시하지 않는다', () {
      expect(formatActivityDuration(null), isNull);
    });

    test('음수는 표시하지 않는다', () {
      expect(formatActivityDuration(-1), isNull);
      expect(formatActivityDuration(-60000), isNull);
    });

    test('1초 미만은 "1초 미만"이다', () {
      expect(formatActivityDuration(0), '1초 미만');
      expect(formatActivityDuration(999), '1초 미만');
    });

    test('1분 미만은 초로 표시한다 — 0분이 되지 않는다', () {
      expect(formatActivityDuration(1000), '1초');
      expect(formatActivityDuration(18309), '18초');
      expect(formatActivityDuration(59999), '59초');
    });

    test('정확히 1분은 "1분"이다', () {
      expect(formatActivityDuration(60000), '1분');
    });

    test('분과 초가 함께 있으면 둘 다 보여준다 — 반올림하지 않는다', () {
      expect(formatActivityDuration(89000), '1분 29초');
      expect(formatActivityDuration(91000), '1분 31초');
      expect(formatActivityDuration(115916), '1분 55초');
    });

    test('초가 0이면 분만 보여준다', () {
      expect(formatActivityDuration(120000), '2분');
    });

    test('1시간 이상은 시간 단위로 올린다', () {
      expect(formatActivityDuration(3600000), '1시간');
      expect(formatActivityDuration(3660000), '1시간 1분');
      expect(formatActivityDuration(7199999), '1시간 59분');
    });

    test('시간 단위에서는 초를 버린다 — 문구가 길어지는 것을 막는다', () {
      expect(formatActivityDuration(3601000), '1시간');
    });
  });
}
