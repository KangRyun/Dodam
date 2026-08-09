import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/repositories/child_profile_image_repository.dart';
import '../../domain/repositories/child_repository.dart';
import '../dto/child_dtos.dart';

final class RemoteChildRepository
    implements ChildRepository, ChildProfileImageRepository {
  const RemoteChildRepository(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    final response = await _apiClient.get<Object?>('children');
    return envelopeList(response.data)
        .map((item) => ChildSummaryDto.fromJson(jsonObject(item)))
        .toList(growable: false);
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'children',
      data: request.toJson(),
    );
    return ChildDetailDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<ChildDetailDto> getChild(int childId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId',
    );
    return ChildDetailDto.fromJson(envelopeObject(response.data));
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
    return ChildDetailDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<ChildProfileImageUploadResponseDto> uploadProfileImage(
    ChildProfileImageUpload image, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'child-profile-images',
      data: FormData.fromMap({
        'image': MultipartFile.fromBytes(
          image.bytes,
          filename: image.fileName,
          contentType: DioMediaType.parse(image.mimeType),
        ),
      }),
      onSendProgress: onSendProgress,
    );
    return ChildProfileImageUploadResponseDto.fromJson(
      envelopeObject(response.data),
    );
  }

  @override
  Future<Uint8List> downloadProfileImage(String relativeUrl) async {
    final path = _childProfileImageApiPath(relativeUrl);
    final response = await _apiClient.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Child profile image response is empty.');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteChild(int childId) async {
    await _apiClient.delete<void>(
      'children/$childId',
      data: const {'confirmation': 'DELETE'},
    );
  }

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/tutorial',
    );
    return TutorialProgressDto.fromJson(envelopeObject(response.data));
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
    return TutorialProgressDto.fromJson(envelopeObject(response.data));
  }
}

String _childProfileImageApiPath(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(url, 'url');
  }
  final match = RegExp(
    r'^/api/v1/child-profile-images/([A-Za-z0-9-]+)/file$',
  ).firstMatch(uri.path);
  if (match == null) throw ArgumentError.value(url, 'url');
  return 'child-profile-images/${match.group(1)}/file';
}
