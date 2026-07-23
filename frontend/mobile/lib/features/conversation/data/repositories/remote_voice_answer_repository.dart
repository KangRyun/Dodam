import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/voice_answer.dart';
import '../../domain/repositories/voice_answer_repository.dart';

// 음성 파일과 질문 연결 정보를 multipart로 전송
final class RemoteVoiceAnswerRepository implements VoiceAnswerRepository {
  const RemoteVoiceAnswerRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversations/$conversationId/answers/voice',
      data: FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          request.recording.filePath,
          filename: 'voice-answer.m4a',
          contentType: DioMediaType('audio', 'mp4'),
        ),
        'metadata': jsonEncode(request.metadataJson()),
      }),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final body = response.data!;
    final payload = body['data'] is Map
        ? Map<String, dynamic>.from(body['data']! as Map)
        : body;
    return VoiceAnswerUploadResult.fromJson(payload);
  }
}
