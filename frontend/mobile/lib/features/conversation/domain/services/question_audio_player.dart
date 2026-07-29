import 'dart:typed_data';

typedef QuestionAudioPlayerFactory = QuestionAudioPlayer Function();

abstract interface class QuestionAudioPlayer {
  Future<void> play(Uint8List bytes, {required String mimeType});

  Future<void> stop();

  Future<void> dispose();
}
