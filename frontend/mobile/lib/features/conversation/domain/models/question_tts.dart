import 'dart:typed_data';

final class QuestionTtsRequest {
  const QuestionTtsRequest({
    this.voice = 'CHILD_FRIENDLY_01',
    this.speed = 1.0,
  });

  final String voice;
  final double speed;

  Map<String, dynamic> toJson() => {'voice': voice, 'speed': speed};
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
