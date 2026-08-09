import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/data/repositories/remote_child_repository.dart';
import 'package:dodam/features/child/domain/repositories/child_profile_image_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profileImageFileId PATCH 삼상태', () {
    test('unchanged는 key를 생략한다', () {
      const request = UpdateChildRequestDto(nickname: '민지');

      expect(request.toJson(), isNot(contains('profileImageFileId')));
    });

    test('clear는 명시적 null을 보낸다', () {
      const request = UpdateChildRequestDto(
        profileImage: ProfileImageUpdate.clear(),
      );

      expect(request.toJson(), containsPair('profileImageFileId', null));
    });

    test('replace는 새 file id를 보낸다', () {
      const request = UpdateChildRequestDto(
        profileImage: ProfileImageUpdate.replace('profile-file-828'),
      );

      expect(
        request.toJson(),
        containsPair('profileImageFileId', 'profile-file-828'),
      );
    });

    test('신규 등록은 ID가 없으면 생략하고 있으면 포함한다', () {
      const base = CreateChildRequestDto(
        nickname: '민지',
        birthDate: '2020-03-02',
        relationshipType: 'MOTHER',
        questionDifficulty: 'PRESCHOOL',
        responseModes: ['VOICE'],
      );
      const withPhoto = CreateChildRequestDto(
        nickname: '민지',
        birthDate: '2020-03-02',
        relationshipType: 'MOTHER',
        questionDifficulty: 'PRESCHOOL',
        responseModes: ['VOICE'],
        profileImageFileId: 'profile-file-828',
      );

      expect(base.toJson(), isNot(contains('profileImageFileId')));
      expect(
        withPhoto.toJson(),
        containsPair('profileImageFileId', 'profile-file-828'),
      );
    });
  });

  test('S755 upload는 인증 client로 image multipart를 보내고 201 응답을 파싱한다', () async {
    final interceptor = _ProfileImageInterceptor();
    final repository = RemoteChildRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        accessTokenProvider: const _TokenProvider(),
        interceptors: [interceptor],
      ),
    );

    final response = await repository.uploadProfileImage(
      ChildProfileImageUpload(
        bytes: Uint8List.fromList(const [0x89, 0x50, 0x4e, 0x47]),
        fileName: 'child.png',
        mimeType: 'image/png',
      ),
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/child-profile-images');
    expect(request.headers['Authorization'], 'Bearer access-828');
    final form = request.data as FormData;
    expect(form.files.map((entry) => entry.key), ['image']);
    expect(form.files.single.value.filename, 'child.png');
    expect(form.files.single.value.contentType.toString(), 'image/png');
    expect(response.profileImageFileId, 'profile-file-828');
    expect(response.fileSizeBytes, 4);
  });

  test('S755 오류는 공통 ApiFailure로 변환한다', () async {
    final repository = RemoteChildRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [_ProfileImageInterceptor(fail: true)],
      ),
    );

    await expectLater(
      repository.uploadProfileImage(
        ChildProfileImageUpload(
          bytes: Uint8List(1),
          fileName: 'bad.webp',
          mimeType: 'image/webp',
        ),
      ),
      throwsA(isA<ApiResponseFailure>()),
    );
  });

  test('인증 proxy 상대 URL은 API prefix를 안전하게 정규화해 bytes로 받는다', () async {
    final interceptor = _DownloadInterceptor();
    final repository = RemoteChildRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        accessTokenProvider: const _TokenProvider(),
        interceptors: [interceptor],
      ),
    );

    final bytes = await repository.downloadProfileImage(
      '/api/v1/child-profile-images/file-828/file',
    );

    expect(bytes, [1, 2, 3]);
    expect(
      interceptor.requests.single.uri.path,
      '/api/v1/child-profile-images/file-828/file',
    );
    expect(
      interceptor.requests.single.headers['Authorization'],
      'Bearer access-828',
    );
  });
}

final class _TokenProvider implements AccessTokenProvider {
  const _TokenProvider();

  @override
  Future<String?> readAccessToken() async => 'access-828';
}

final class _ProfileImageInterceptor extends Interceptor {
  _ProfileImageInterceptor({this.fail = false});

  final bool fail;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (fail) {
      handler.reject(
        DioException.badResponse(
          statusCode: 415,
          requestOptions: options,
          response: Response<Object?>(
            requestOptions: options,
            statusCode: 415,
            data: const {
              'success': false,
              'code': 'CHILD_PROFILE_IMAGE_UNSUPPORTED_TYPE',
              'message': 'unsupported',
            },
          ),
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 201,
        data: const {
          'success': true,
          'code': 'COMMON_201',
          'message': 'created',
          'data': {
            'profileImageFileId': 'profile-file-828',
            'contentType': 'image/png',
            'fileSizeBytes': 4,
            'widthPx': 512,
            'heightPx': 512,
            'expiresAt': '2026-08-03T12:00:00Z',
          },
        },
      ),
    );
  }
}

final class _DownloadInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<List<int>>(
        requestOptions: options,
        statusCode: 200,
        data: const [1, 2, 3],
      ),
    );
  }
}
