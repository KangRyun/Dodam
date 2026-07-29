import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/question_tts.dart';
import '../../domain/repositories/question_tts_repository.dart';

final class RemoteQuestionTtsRepository implements QuestionTtsRepository {
  const RemoteQuestionTtsRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<QuestionTtsAudio> loadQuestionAudio(
    int messageId, {
    QuestionTtsRequest request = const QuestionTtsRequest(),
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversation-messages/$messageId/tts',
      data: request.toJson(),
    );
    final body = response.data;
    if (body == null || body['data'] is! Map) {
      throw const FormatException('TTS response data is missing');
    }
    final tts = QuestionTtsResponse.fromJson(
      Map<String, dynamic>.from(body['data']! as Map),
    );
    final audioPath = _audioPath(tts.audioUrl, messageId);
    final audioResponse = await _apiClient.get<List<int>>(
      audioPath,
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': 'audio/mpeg'},
      ),
    );
    final bytes = audioResponse.data;
    final mimeType = audioResponse.headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('TTS audio bytes are missing');
    }
    if (mimeType != 'audio/mpeg') {
      throw const FormatException('Unexpected TTS audio content type');
    }
    return QuestionTtsAudio(
      bytes: Uint8List.fromList(bytes),
      mimeType: mimeType!,
    );
  }

  String _audioPath(String audioUrl, int messageId) {
    final expected = '/api/v1/conversation-messages/$messageId/audio';
    if (audioUrl != expected) {
      throw const FormatException('Unexpected TTS audio path');
    }
    return audioUrl.substring('/api/v1/'.length);
  }
}
