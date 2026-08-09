import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/activity_conversation_turn.dart';
import '../../domain/repositories/activity_repository.dart';
import '../dto/activity_dtos.dart';

/// CONV-02가 허용하는 최대 페이지 크기(백엔드 `MAX_PAGE_SIZE`)와 같다.
const int _messagePageSize = 100;

/// 한 대화에서 이어 읽을 페이지 수 상한. 응답의 `hasNext`가 끝나지 않아도
/// 무한히 요청하지 않도록 두는 안전장치이며, 실제 대화 길이(질문 수 상한)를
/// 크게 웃돈다.
const int _maxMessagePages = 20;

final class RemoteActivityRepository implements ActivityRepository {
  const RemoteActivityRepository(this._apiClient);
  final ApiClient _apiClient;
  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/drawing-sessions',
      queryParameters: filter.toQueryParameters(),
    );
    return ApiPage.fromJson(
      envelopeObject(response.data),
      ActivitySummaryDto.fromJson,
    );
  }

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'drawing-sessions/$activityId',
    );
    return ActivityDetailDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<void> deleteActivity(int activityId) async =>
      _apiClient.delete<void>('drawing-sessions/$activityId');

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) async {
    final collected = <ActivityConversationMessageDto>[];
    for (var page = 0; page < _maxMessagePages; page += 1) {
      final response = await _apiClient.get<Map<String, dynamic>>(
        'conversations/$conversationId/messages',
        queryParameters: {'page': page, 'size': _messagePageSize},
      );
      final body = envelopeObject(response.data);
      final content = (body['content'] as List<dynamic>?) ?? const [];
      for (final item in content) {
        collected.add(
          ActivityConversationMessageDto.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        );
      }
      // 빈 페이지는 hasNext가 잘못 남아 있어도 더 읽을 것이 없다는 뜻이다.
      if (content.isEmpty || (body['hasNext'] as bool? ?? false) == false) {
        break;
      }
    }
    // 페이지 경계에서 같은 메시지가 두 번 오거나 순번이 뒤섞여 와도
    // 화면이 그대로 쓸 수 있도록 여기서 정리해 내려준다.
    return ActivityConversationTurn.order(collected);
  }

  @override
  Future<Uint8List> downloadImage(String url) async {
    final path = _activityImageApiPath(url);
    final response = await _apiClient.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Activity image response is empty.');
    }
    return Uint8List.fromList(bytes);
  }
}

String _activityImageApiPath(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(url, 'url');
  }
  final match = RegExp(
    r'^/api/v1/drawing-assets/([1-9][0-9]*)/file$',
  ).firstMatch(uri.path);
  if (match == null) {
    throw ArgumentError.value(url, 'url');
  }
  return 'drawing-assets/${match.group(1)}/file';
}
