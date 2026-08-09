/// 서버 TTS가 실패했을 때 기기 자체 음성으로 질문을 읽어 주는 마지막 수단이다.
///
/// 서버 오디오와 달리 목소리를 고를 수 없고 억양도 캐릭터와 다르다. 그래도 필요한 이유는
/// **글을 못 읽는 아이에게 질문이 닿아야 하기 때문**이다. 미취학 아이에게 서버 TTS 실패는
/// 곧 활동 중단이다 — 화면에 글자만 남으면 무엇을 하라는 것인지 알 수 없다.
///
/// 실패해도 예외를 던지지 않고 `false`를 돌려준다. 이 자리는 이미 한 번 실패한 경로의
/// 끝이라, 여기서 예외가 올라가면 보기 선택·건너뛰기까지 함께 막힌다.
abstract interface class QuestionSpeechSynthesizer {
  /// 질문 문장을 기기 음성으로 읽는다.
  ///
  /// @param text 읽어 줄 질문 문장
  /// @return 재생을 시작했으면 `true`, 기기가 한국어 음성을 갖고 있지 않거나 실패하면 `false`
  Future<bool> speak(String text);

  /// 재생 중인 기기 음성을 멈춘다.
  Future<void> stop();
}

/// 기기 음성을 쓰지 않는 구현이다.
///
/// 테스트와, 음성 합성을 붙이지 않은 플랫폼에서 쓴다. 언제나 `false`를 돌려주므로 호출부는
/// 수동 재생 버튼을 남기는 경로로 이어진다.
final class NoopQuestionSpeechSynthesizer implements QuestionSpeechSynthesizer {
  const NoopQuestionSpeechSynthesizer();

  @override
  Future<bool> speak(String text) async => false;

  @override
  Future<void> stop() async {}
}
