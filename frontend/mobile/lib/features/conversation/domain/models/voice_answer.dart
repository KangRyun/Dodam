import 'voice_recording.dart';

final class VoiceAnswerUploadRequest {
  const VoiceAnswerUploadRequest({
    required this.questionMessageId,
    required this.recording,
  });

  final int questionMessageId;
  final VoiceRecording recording;

  Map<String, dynamic> metadataJson() => {
    'questionMessageId': questionMessageId,
    'clientStartedAt': recording.startedAt.toUtc().toIso8601String(),
    'clientEndedAt': recording.endedAt.toUtc().toIso8601String(),
    'stopReason': switch (recording.completionReason) {
      VoiceRecordingCompletionReason.manual => 'USER_FINISH',
      VoiceRecordingCompletionReason.silence => 'SILENCE',
      VoiceRecordingCompletionReason.maximumDuration => 'TIMEOUT',
    },
  };
}

final class VoiceAnswerUploadResult {
  const VoiceAnswerUploadResult({
    required this.messageId,
    required this.parentMessageId,
    required this.sequence,
    required this.speechStatus,
  });

  factory VoiceAnswerUploadResult.fromJson(Map<String, dynamic> json) =>
      VoiceAnswerUploadResult(
        messageId: json['messageId'] as int,
        parentMessageId: json['parentMessageId'] as int,
        sequence: json['sequence'] as int,
        speechStatus: json['speechStatus'] as String,
      );

  final int messageId;
  final int parentMessageId;
  final int sequence;
  final String speechStatus;
}
