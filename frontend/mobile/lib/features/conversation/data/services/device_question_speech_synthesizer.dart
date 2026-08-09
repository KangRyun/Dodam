import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/services/question_speech_synthesizer.dart';

/// 기기에 내장된 음성 합성으로 질문을 읽는다 (P0-3 fallback 마지막 단계).
///
/// 서버 TTS → 짧은 재시도 → **여기** → 수동 재생 버튼 순서의 세 번째 자리다.
///
/// 아이용 속도로 늦춘다. 기본 속도는 어른이 정보를 듣기 위한 값이라 미취학 아이에게는 빠르다.
final class DeviceQuestionSpeechSynthesizer implements QuestionSpeechSynthesizer {
  DeviceQuestionSpeechSynthesizer({FlutterTts? tts}) : _injected = tts;

  static const _language = 'ko-KR';
  static const _speechRate = 0.42;

  final FlutterTts? _injected;
  FlutterTts? _created;
  bool _configured = false;

  /// 실제로 읽어 줄 때가 되어서야 만든다.
  ///
  /// [FlutterTts] 는 생성자에서 MethodCallHandler 를 등록하는데, 그 시점에 Flutter binding 이
  /// 아직 없으면 assert 로 죽는다. 앱 조립부는 binding 초기화보다 먼저 도는 경로가 있어
  /// 여기서 만들면 그 경로가 통째로 실패한다.
  ///
  /// 대부분의 활동은 서버 TTS 로 끝나 이 자리까지 오지 않는다. 쓰지도 않을 채널 핸들러를
  /// 매 실행마다 등록할 이유도 없다.
  FlutterTts get _tts => _injected ?? (_created ??= FlutterTts());

  @override
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      if (!await _configure()) return false;
      // 앞의 발화가 남아 있으면 겹쳐 들린다.
      await _tts.stop();
      final result = await _tts.speak(text);
      // Android 는 1, iOS 는 1 또는 null 을 준다. 실패만 1 이 아닌 값으로 온다.
      return result == null || result == 1;
    } on Object catch (caught) {
      if (kDebugMode) {
        debugPrint(
          '[QUESTION_TTS_FALLBACK] speak_failure exceptionType=${caught.runtimeType}',
        );
      }
      return false;
    }
  }

  @override
  Future<void> stop() async {
    // 한 번도 읽어 준 적이 없으면 멈출 것도 없다. 여기서 만들면 쓰지도 않을 채널이 붙는다.
    if (_injected == null && _created == null) return;
    try {
      await _tts.stop();
    } on Object catch (caught) {
      if (kDebugMode) {
        debugPrint(
          '[QUESTION_TTS_FALLBACK] stop_failure exceptionType=${caught.runtimeType}',
        );
      }
    }
  }

  /// 한국어 음성이 실제로 있는지 확인하고 아이용 속도로 맞춘다.
  ///
  /// 언어가 없는 기기에서 그냥 `speak`를 부르면 아무 소리도 나지 않으면서 성공을 돌려준다.
  /// 그러면 호출부는 읽어 준 줄 알고 수동 재생 버튼을 감춘다 — 아이는 글자만 보게 된다.
  Future<bool> _configure() async {
    if (_configured) return true;
    final available = await _tts.isLanguageAvailable(_language);
    if (available != true) return false;
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.awaitSpeakCompletion(true);
    _configured = true;
    return true;
  }
}
