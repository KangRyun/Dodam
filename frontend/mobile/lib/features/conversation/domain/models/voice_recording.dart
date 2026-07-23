enum VoiceRecordingCompletionReason { manual, silence, maximumDuration }

final class VoiceRecording {
  const VoiceRecording({
    required this.filePath,
    required this.duration,
    required this.startedAt,
    required this.endedAt,
    this.completionReason = VoiceRecordingCompletionReason.manual,
  });

  final String filePath;
  final Duration duration;
  final DateTime startedAt;
  final DateTime endedAt;
  final VoiceRecordingCompletionReason completionReason;
}
