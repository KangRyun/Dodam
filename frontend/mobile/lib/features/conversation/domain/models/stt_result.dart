enum SttSpeechStatus { pending, processing, success, failed }

final class SttResult {
  const SttResult({required this.messageId, required this.status, this.text});

  final int messageId;
  final SttSpeechStatus status;
  final String? text;
}
