import '../../../../core/network/network.dart';
import '../../domain/repositories/child_repository.dart';
import '../dto/child_dtos.dart';

final class RemoteChildRepository implements ChildRepository {
  const RemoteChildRepository(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    final response = await _apiClient.get<List<dynamic>>('children');
    return response.data!
        .map((item) => ChildSummaryDto.fromJson(jsonObject(item)))
        .toList(growable: false);
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'children',
      data: request.toJson(),
    );
    return ChildDetailDto.fromJson(response.data!);
  }

  @override
  Future<ChildDetailDto> getChild(int childId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId',
    );
    return ChildDetailDto.fromJson(response.data!);
  }

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      'children/$childId',
      data: request.toJson(),
    );
    return ChildDetailDto.fromJson(response.data!);
  }

  @override
  Future<void> deleteChild(int childId, {bool cascade = true}) async {
    await _apiClient.delete<void>(
      'children/$childId',
      queryParameters: {'cascade': cascade},
    );
  }

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/tutorial',
    );
    return TutorialProgressDto.fromJson(response.data!);
  }

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      'children/$childId/tutorial',
      data: request.toJson(),
    );
    return TutorialProgressDto.fromJson(response.data!);
  }
}
