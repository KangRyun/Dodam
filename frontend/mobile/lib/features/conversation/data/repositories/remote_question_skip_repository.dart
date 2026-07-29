import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/question_skip.dart';
import '../../domain/repositories/question_skip_repository.dart';

/// 질문 건너뛰기를 서버에 기록한다(CONV-08).
///
/// 서버는 `Idempotency-Key`로 재전송을 판별하므로 같은 건너뛰기는 같은 키로 보낸다.
/// 이미 건너뛴 질문의 재요청도 성공으로 응답한다.
final class RemoteQuestionSkipRepository implements QuestionSkipRepository {
  const RemoteQuestionSkipRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversations/$conversationId/skip',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return QuestionSkipResult.fromJson(envelopeObject(response.data));
  }
}
