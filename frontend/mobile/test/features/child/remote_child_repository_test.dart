import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/data/repositories/remote_child_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('아동 등록 API에 백엔드 허용 캐릭터 코드를 전송한다', () async {
    final interceptor = _ChildRegistrationInterceptor();
    final repository = RemoteChildRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final child = await repository.createChild(
      const CreateChildRequestDto(
        nickname: '민지',
        birthDate: '2020-03-02',
        relationshipType: 'MOTHER',
        preferredCharacter: 'BEAR',
        questionDifficulty: 'PRESCHOOL',
        responseModes: ['VOICE'],
      ),
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/children');
    expect(request.data['preferredCharacter'], 'BASE');
    expect(child.preferredCharacter, 'BASE');
  });
}

final class _ChildRegistrationInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 201,
        data: const {
          'success': true,
          'code': 'COMMON_201',
          'message': '요청에 성공했습니다.',
          'data': {
            'childId': 77,
            'nickname': '민지',
            'birthDate': '2020-03-02',
            'age': 6,
            'profileImageUrl': null,
            'preferredCharacter': 'BASE',
            'questionDifficulty': 'PRESCHOOL',
            'responseModes': ['VOICE'],
            'tutorialStatus': 'NOT_STARTED',
            'profileStatus': 'ACTIVE',
            'relationshipType': 'MOTHER',
            'createdAt': '2026-07-31T09:00:00Z',
            'updatedAt': '2026-07-31T09:00:00Z',
          },
        },
      ),
    );
  }
}
