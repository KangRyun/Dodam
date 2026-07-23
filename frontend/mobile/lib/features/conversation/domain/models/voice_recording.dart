enum VoiceRecordingCompletionReason { manual, silence, maximumDuration }

final class VoiceRecording {
  const VoiceRecording({
    required this.filePath,
    required this.duration,
    this.completionReason = VoiceRecordingCompletionReason.manual,
  });

  final String filePath;
  final Duration duration;
  final VoiceRecordingCompletionReason completionReason;
}
