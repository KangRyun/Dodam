import 'dart:typed_data';

/// 서버가 허용한 질문 TTS 전달 방식 프리셋이다.
///
/// 캐릭터 고유 voice와 분리해 전송한다. 자유 텍스트 지시는 앱에서 만들지 않고,
/// 아이의 실제 참여 흐름에서만 다음 질문의 프리셋을 선택한다.
enum QuestionTtsToneProfile {
  characterDefault('CHARACTER_DEFAULT_V1'),
  characterCelebrating('CHARACTER_CELEBRATING_V1'),
  characterEncouraging('CHARACTER_ENCOURAGING_V1');

  const QuestionTtsToneProfile(this.value);

  final String value;
}

final class QuestionTtsRequest {
  const QuestionTtsRequest({
    this.voice = 'CHILD_FRIENDLY_01',
    this.speed = 1.0,
    this.toneProfile = QuestionTtsToneProfile.characterDefault,
  });

  final String voice;
  final double speed;
  final QuestionTtsToneProfile toneProfile;

  QuestionTtsRequest copyWith({QuestionTtsToneProfile? toneProfile}) =>
      QuestionTtsRequest(
        voice: voice,
        speed: speed,
        toneProfile: toneProfile ?? this.toneProfile,
      );

  Map<String, dynamic> toJson() => {
    'voice': voice,
    'speed': speed,
    'toneProfile': toneProfile.value,
  };
}

final class QuestionTtsResponse {
  const QuestionTtsResponse({
    required this.audioUrl,
    required this.expiresAt,
    required this.durationMs,
    required this.subtitle,
  });

  factory QuestionTtsResponse.fromJson(Map<String, dynamic> json) =>
      QuestionTtsResponse(
        audioUrl: json['audioUrl'] as String,
        expiresAt: switch (json['expiresAt']) {
          final String value => DateTime.parse(value),
          _ => null,
        },
        durationMs: switch (json['durationMs']) {
          final num value => value.toInt(),
          _ => null,
        },
        subtitle: json['subtitle'] as String,
      );

  final String audioUrl;
  final DateTime? expiresAt;
  final int? durationMs;
  final String subtitle;
}

final class QuestionTtsAudio {
  const QuestionTtsAudio({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}
