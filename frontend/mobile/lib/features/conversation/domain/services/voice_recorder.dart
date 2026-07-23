abstract interface class VoiceRecorder {
  Future<void> start();

  Future<double> readAmplitude();

  Future<String?> stop();

  Future<void> cancel();

  Future<void> dispose();
}
