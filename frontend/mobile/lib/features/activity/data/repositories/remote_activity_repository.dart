import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/repositories/activity_repository.dart';
import '../dto/activity_dtos.dart';

final class RemoteActivityRepository implements ActivityRepository {
  const RemoteActivityRepository(this._apiClient);
  final ApiClient _apiClient;
  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/activities',
      queryParameters: filter.toQueryParameters(),
    );
    return ApiPage.fromJson(response.data!, ActivitySummaryDto.fromJson);
  }

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'activities/$activityId',
    );
    return ActivityDetailDto.fromJson(response.data!);
  }

  @override
  Future<void> deleteActivity(int activityId) async =>
      _apiClient.delete<void>('activities/$activityId');

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
