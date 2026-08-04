/// 그림 심리 상담 리포트의 활동 시간(밀리초)을 보호자가 읽을 문구로 바꾼다.
///
/// 이전 구현은 `(durationMs / 60000).round()` 로 분만 표시해서, 1분 미만 활동이
/// 전부 `0분` 이 됐다(S15P11B209-859). 18초 동안 그림을 그리고 대화까지 마친
/// 활동이 "0분"으로 보이면 보호자에게는 아무것도 하지 않은 것으로 읽힌다.
///
/// 그래서 두 가지를 바꿨다.
///
/// 1. 1분 미만은 초로 표시한다 — 짧은 활동도 실제 값을 보여준다.
/// 2. 반올림하지 않고 **버린다**. 반올림은 89초를 `1분`, 91초를 `2분` 으로 보이게
///    해 실제보다 길게 말한다. 활동 시간은 과장하지 않는 편이 안전하다.
///
/// 값이 없거나 음수면 `null` 을 돌려주고, 호출부는 그 줄을 그리지 않는다. 음수는
/// 서버가 줄 수 없는 값이지만(완료 시각 - 시작 시각), 시계 역행이나 집계 결함으로
/// 들어와도 "-1분" 같은 문구를 보이지 않게 막는다.
String? formatActivityDuration(int? durationMs) {
  if (durationMs == null || durationMs < 0) return null;

  final totalSeconds = durationMs ~/ 1000;
  if (totalSeconds < 1) return '1초 미만';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
  }
  if (minutes > 0) {
    return seconds == 0 ? '$minutes분' : '$minutes분 $seconds초';
  }
  return '$seconds초';
}
