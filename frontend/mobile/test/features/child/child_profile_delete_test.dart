import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dodam/app/app.dart';
import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/data/repositories/remote_child_repository.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 아동 프로필 삭제(S15P11B209-844).
///
/// 삭제 진입은 프로필 선택 화면의 편집 모드에서만 열리므로, 화면 단위로 위젯을
/// 세우지 않고 [DodamApp]의 실제 router·화면·컨트롤러를 그대로 거쳐 검증한다.
/// 삭제 확인 값과 endpoint는 실제 [RemoteChildRepository]로 따로 확인한다.
void main() {
  group('삭제 진입 노출', () {
    testWidgets('편집 모드에서 고른 아이의 편집 화면에만 삭제 버튼이 있다', (tester) async {
      final repository = _ChildRepository([_child(id: 3, nickname: '하늘')]);
      await _bootProfileEditing(tester, repository);

      await _openEditor(tester, childId: 3);

      expect(find.text('아이 프로필 편집'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('delete-child-profile')),
        findsOneWidget,
      );
    });

    testWidgets('신규 등록 화면에는 삭제 버튼이 없다', (tester) async {
      final repository = _ChildRepository([_child(id: 3)]);
      await _bootProfileSelection(tester, repository);

      await tester.tap(find.byKey(const ValueKey('add-child-profile')));
      await tester.pumpAndSettle();

      expect(find.text('아이 등록'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-child-profile')), findsNothing);
      expect(repository.deletedIds, isEmpty);
    });
  });

  group('확인 다이얼로그', () {
    testWidgets('삭제 대상 아이 이름과 기록 영향을 안내한다', (tester) async {
      final repository = _ChildRepository([_child(id: 3, nickname: '하늘')]);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 3);

      await _tapDelete(tester);

      expect(find.text('아이 프로필을 삭제할까요?'), findsOneWidget);
      expect(
        find.text('하늘의 그림과 대화, 활동 기록도 함께 삭제되며 되돌릴 수 없어요.'),
        findsOneWidget,
      );
      expect(find.text('취소'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('취소하면 삭제 API를 부르지 않고 편집 화면에 그대로 있다', (tester) async {
      final repository = _ChildRepository([_child(id: 3, nickname: '하늘')]);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 3);
      await _tapDelete(tester);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, isEmpty);
      expect(repository.getChildrenCalls, 1);
      expect(find.text('아이 프로필 편집'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('delete-child-profile')),
        findsOneWidget,
      );
    });

    testWidgets('system back으로 다이얼로그를 닫아도 삭제 API를 부르지 않는다', (tester) async {
      final repository = _ChildRepository([_child(id: 3, nickname: '하늘')]);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 3);
      await _tapDelete(tester);

      await _systemBack(tester);

      expect(find.text('아이 프로필을 삭제할까요?'), findsNothing);
      expect(repository.deletedIds, isEmpty);
      expect(find.text('아이 프로필 편집'), findsOneWidget);
    });
  });

  group('삭제 성공', () {
    testWidgets('정확한 아이 ID로 삭제하고 목록을 다시 받아 편집 화면을 벗어난다', (tester) async {
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘'),
        _child(id: 7, nickname: '바다'),
      ]);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 7);

      await _confirmDelete(tester);

      expect(repository.deletedIds, [7]);
      // 삭제 후 서버 목록을 다시 받는다(부팅 1회 + 삭제 후 1회).
      expect(repository.getChildrenCalls, 2);
      expect(find.text('아이 프로필 편집'), findsNothing);
      expect(find.byType(ProfileSelectionScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('child-profile-7')), findsNothing);
      expect(find.byKey(const ValueKey('child-profile-3')), findsOneWidget);
    });

    testWidgets('선택되지 않은 아이를 삭제하면 현재 선택이 유지된다', (tester) async {
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘'),
        _child(id: 7, nickname: '바다'),
      ]);
      await _bootProfileEditing(tester, repository);
      // 부팅 시 첫 아이가 자동 선택된다.
      expect(_controller(tester).selectedChildId, 3);

      await _openEditor(tester, childId: 7);
      await _confirmDelete(tester);

      expect(_controller(tester).selectedChildId, 3);
      expect(_controller(tester).children.map((child) => child.childId), [3]);
    });

    testWidgets('현재 선택 아이를 삭제하면 선택이 삭제 대상에 남지 않는다', (tester) async {
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘'),
        _child(id: 7, nickname: '바다'),
      ]);
      await _bootProfileEditing(tester, repository);
      expect(_controller(tester).selectedChildId, 3);

      await _openEditor(tester, childId: 3);
      await _confirmDelete(tester);

      final controller = _controller(tester);
      expect(controller.selectedChildId, isNot(3));
      // 남은 아이는 기존 자동 선택 정책(목록 첫 아이)을 그대로 따르고, 사용자가
      // 직접 고른 상태로 승격하지 않는다.
      expect(controller.selectedChildId, 7);
      expect(controller.hasExplicitChildSelection, isFalse);
    });

    testWidgets('마지막 아이를 삭제하면 아이 추가 상태가 된다', (tester) async {
      final repository = _ChildRepository([_child(id: 3, nickname: '하늘')]);
      await _bootProfileEditing(tester, repository);

      await _openEditor(tester, childId: 3);
      await _confirmDelete(tester);

      final controller = _controller(tester);
      expect(controller.status, ChildListStatus.empty);
      expect(controller.selectedChildId, isNull);
      expect(find.byKey(const ValueKey('child-profile-grid')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-child-profile')), findsOneWidget);
      expect(find.byKey(const ValueKey('child-profile-3')), findsNothing);
    });

    testWidgets('삭제는 프로필 사진·캐릭터 수정 요청을 함께 보내지 않는다', (tester) async {
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘', preferredCharacter: 'DINO'),
        _child(id: 7, nickname: '바다'),
      ]);
      await _bootProfileEditing(tester, repository);

      await _openEditor(tester, childId: 3);
      await _confirmDelete(tester);

      expect(repository.deletedIds, [3]);
      expect(repository.updateRequests, isEmpty);
      expect(repository.createRequests, isEmpty);
    });
  });

  group('single-flight와 진행 상태', () {
    testWidgets('삭제 중에는 버튼이 진행 상태로 잠기고 DELETE는 한 번이다', (tester) async {
      final pending = Completer<void>();
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘'),
        _child(id: 7, nickname: '바다'),
      ], deleteGate: pending);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 3);

      await _tapDelete(tester);
      await tester.tap(find.text('삭제'));
      await _flush(tester);

      expect(find.text('아이 프로필을 삭제할까요?'), findsNothing);
      final button = find.byKey(const ValueKey('delete-child-profile'));
      expect(tester.widget<AppButton>(button).isLoading, isTrue);

      // 진행 중 재탭은 다이얼로그를 다시 열지 않는다.
      await tester.tap(button);
      await _flush(tester);
      expect(find.text('아이 프로필을 삭제할까요?'), findsNothing);

      pending.complete();
      await tester.pumpAndSettle();

      expect(repository.deletedIds, [3]);
      expect(find.byType(ProfileSelectionScreen), findsOneWidget);
    });

    testWidgets('삭제 응답 전에 편집 화면을 벗어나도 늦은 응답이 예외를 만들지 않는다', (tester) async {
      final pending = Completer<void>();
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘'),
        _child(id: 7, nickname: '바다'),
      ], deleteGate: pending);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 3);

      await _tapDelete(tester);
      await tester.tap(find.text('삭제'));
      await _flush(tester);

      // 요청이 떠 있는 동안 system back으로 편집 화면을 벗어난다. 화면이 빠지면
      // 진행 spinner도 함께 사라지므로 여기서는 settle이 끝난다.
      await _systemBack(tester);
      expect(find.text('아이 프로필 편집'), findsNothing);

      pending.complete();
      await _flush(tester);

      expect(repository.deletedIds, [3]);
      expect(tester.takeException(), isNull);
      // 늦은 응답이 새 화면을 덮어쓰거나 되돌리지 않는다.
      expect(find.byType(ProfileSelectionScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('child-profile-7')), findsOneWidget);
    });
  });

  group('삭제 실패', () {
    for (final failure in _failures) {
      testWidgets('${failure.label}이면 화면과 목록을 유지하고 재시도를 안내한다', (tester) async {
        final repository = _ChildRepository([
          _child(id: 3, nickname: '하늘'),
          _child(id: 7, nickname: '바다'),
        ], deleteError: failure.error);
        await _bootProfileEditing(tester, repository);
        await _openEditor(tester, childId: 3);

        await _confirmDelete(tester);

        expect(repository.deletedIds, [3]);
        expect(find.text('아이 프로필 편집'), findsOneWidget);
        expect(find.text('아이 프로필을 삭제하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
        // 기술 오류 코드는 사용자에게 노출하지 않는다.
        expect(find.textContaining('CHILD_'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        final button = find.byKey(const ValueKey('delete-child-profile'));
        expect(tester.widget<AppButton>(button).isLoading, isFalse);
      });
    }

    testWidgets('실패한 아이는 목록에서 사라지지 않고 재시도로 삭제된다', (tester) async {
      final repository = _ChildRepository([
        _child(id: 3, nickname: '하늘'),
        _child(id: 7, nickname: '바다'),
      ], deleteFailuresRemaining: 1);
      await _bootProfileEditing(tester, repository);
      await _openEditor(tester, childId: 3);

      await _confirmDelete(tester);
      expect(_controller(tester).children.map((child) => child.childId), [
        3,
        7,
      ]);

      await _confirmDelete(tester);

      expect(repository.deletedIds, [3, 3]);
      expect(_controller(tester).children.map((child) => child.childId), [7]);
      expect(find.byType(ProfileSelectionScreen), findsOneWidget);
    });
  });

  group('삭제 요청 계약', () {
    test('CHILD-05는 경로에 아이 ID를 담고 본문에 확인 값만 보낸다', () async {
      final interceptor = _DeleteInterceptor();
      final repository = RemoteChildRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      );

      await repository.deleteChild(42);

      final request = interceptor.requests.single;
      expect(request.method, 'DELETE');
      expect(request.uri.path, '/api/v1/children/42');
      // 서버가 지원하지 않는 cascade Query는 붙이지 않는다(COMMON_400_001).
      expect(request.uri.queryParameters, isEmpty);
      final body = Map<String, dynamic>.from(request.data as Map);
      expect(body, {'confirmation': 'DELETE'});
      // 서버 DeleteChildRequest에 없는 필드는 보내지 않는다.
      expect(body.containsKey('profileImageFileId'), isFalse);
      expect(body.containsKey('preferredCharacter'), isFalse);
    });

    test('본문 없는 204 응답을 성공으로 처리한다', () async {
      final repository = RemoteChildRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [_DeleteInterceptor()],
        ),
      );

      await expectLater(repository.deleteChild(42), completes);
    });

    test('확인 값 불일치는 CHILD_400_002 실패로 전달한다', () async {
      final repository = RemoteChildRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [
            _DeleteErrorInterceptor(
              statusCode: 400,
              code: 'CHILD_400_002',
              message: '아동 삭제 확인 값이 올바르지 않습니다.',
            ),
          ],
        ),
      );

      await expectLater(
        repository.deleteChild(42),
        throwsA(
          isA<ApiResponseFailure>()
              .having((failure) => failure.statusCode, 'statusCode', 400)
              .having(
                (failure) => failure.error?.code,
                'code',
                'CHILD_400_002',
              ),
        ),
      );
    });

    test('없는 아이와 다른 보호자 연결은 각각 404·409로 전달한다', () async {
      Future<void> expectFailure(
        int statusCode,
        String code,
        String message,
      ) async {
        final repository = RemoteChildRepository(
          ApiClient(
            environment: ApiEnvironment.fromBaseUrl('https://example.test'),
            interceptors: [
              _DeleteErrorInterceptor(
                statusCode: statusCode,
                code: code,
                message: message,
              ),
            ],
          ),
        );
        await expectLater(
          repository.deleteChild(42),
          throwsA(
            isA<ApiResponseFailure>()
                .having(
                  (failure) => failure.statusCode,
                  'statusCode',
                  statusCode,
                )
                .having((failure) => failure.error?.code, 'code', code),
          ),
        );
      }

      await expectFailure(404, 'CHILD_404_001', '아동 정보를 찾을 수 없습니다.');
      await expectFailure(409, 'CHILD_409_001', '다른 보호자가 연결된 아동은 삭제할 수 없습니다.');
    });
  });
}

typedef _Failure = ({String label, Object error});

const _failures = <_Failure>[
  (
    label: '확인 값 오류(400)',
    error: ApiResponseFailure(statusCode: 400, error: null),
  ),
  (
    label: '없는 아이(404)',
    error: ApiResponseFailure(statusCode: 404, error: null),
  ),
  (
    label: '서버 오류(500)',
    error: ApiResponseFailure(statusCode: 500, error: null),
  ),
  (
    label: '네트워크 끊김',
    error: ApiTransportFailure(type: ApiTransportFailureType.connection),
  ),
];

/// 보호자 홈에서 프로필 선택 화면까지 실제 경로로 이동한다.
Future<void> _bootProfileSelection(
  WidgetTester tester,
  _ChildRepository repository,
) async {
  // 보호자 홈은 태블릿 사이드바 레이아웃이라 태블릿 크기로 검증한다.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(DodamApp(childRepository: repository));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('guardian-switch-profile')));
  await tester.pumpAndSettle();
  expect(find.byType(ProfileSelectionScreen), findsOneWidget);
}

/// 프로필 선택 화면의 "프로필 편집" 모드까지 켠다.
Future<void> _bootProfileEditing(
  WidgetTester tester,
  _ChildRepository repository,
) async {
  await _bootProfileSelection(tester, repository);
  await tester.tap(find.byKey(const ValueKey('profile-selection-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('edit-child-profiles')));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester, {required int childId}) async {
  // 편집 모드의 카드 탭은 삭제 대상 고르기라, 편집 화면은 카드의 연필로 연다
  // (S15P11B209-920).
  final editButton = find.byKey(ValueKey('child-profile-edit-$childId'));
  await tester.ensureVisible(editButton);
  await tester.tap(editButton);
  await tester.pumpAndSettle();
  expect(find.text('아이 프로필 편집'), findsOneWidget);
}

Future<void> _tapDelete(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('delete-child-profile'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await _tapDelete(tester);
  await tester.tap(find.text('삭제'));
  await tester.pumpAndSettle();
}

/// Android system back(하드웨어 뒤로가기)을 그대로 흘려보낸다.
Future<void> _pressSystemBack(WidgetTester tester) async {
  final state = tester.state<State<StatefulWidget>>(find.byType(WidgetsApp));
  // ignore: avoid_dynamic_calls
  await (state as dynamic).didPopRoute();
}

Future<void> _systemBack(WidgetTester tester) async {
  await _pressSystemBack(tester);
  await tester.pumpAndSettle();
}

/// 진행 중 spinner가 계속 프레임을 요청하는 구간에서 전환 애니메이션만 끝낸다.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // 전환이 끝난 route가 트리에서 실제로 빠지는 프레임.
  await tester.pump();
}

/// 화면이 실제로 쓰는 production 컨트롤러 인스턴스.
///
/// 편집 화면이 위에 덮여 offstage가 된 동안에도 같은 인스턴스를 봐야 한다.
GuardianChildController _controller(WidgetTester tester) => tester
    .widget<ProfileSelectionScreen>(
      find.byType(ProfileSelectionScreen, skipOffstage: false),
    )
    .controller;

ChildSummaryDto _child({
  required int id,
  String nickname = '도담이',
  int age = 7,
  String preferredCharacter = 'BASE',
}) => ChildSummaryDto(
  childId: id,
  nickname: nickname,
  birthDate: '2019-04-05',
  age: age,
  profileImageUrl: null,
  preferredCharacter: preferredCharacter,
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'NOT_STARTED',
  relationshipType: 'MOTHER',
  recentActivity: const ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

final class _ChildRepository implements ChildRepository {
  _ChildRepository(
    List<ChildSummaryDto> children, {
    this.deleteGate,
    this.deleteError,
    this.deleteFailuresRemaining = 0,
  }) : _children = [...children];

  final List<ChildSummaryDto> _children;

  /// 완료 시점을 테스트가 잡아야 하는 경우의 지연 지점.
  final Completer<void>? deleteGate;
  final Object? deleteError;
  int deleteFailuresRemaining;

  final List<int> deletedIds = [];
  final List<UpdateChildRequestDto> updateRequests = [];
  final List<CreateChildRequestDto> createRequests = [];
  int getChildrenCalls = 0;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCalls += 1;
    return List.unmodifiable(_children);
  }

  @override
  Future<void> deleteChild(int childId) async {
    deletedIds.add(childId);
    if (deleteGate case final gate?) await gate.future;
    if (deleteError case final error?) throw error;
    if (deleteFailuresRemaining > 0) {
      deleteFailuresRemaining -= 1;
      throw const ApiResponseFailure(statusCode: 500, error: null);
    }
    _children.removeWhere((child) => child.childId == childId);
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async {
    createRequests.add(request);
    throw UnimplementedError();
  }

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) async {
    updateRequests.add(request);
    throw UnimplementedError();
  }

  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

final class _DeleteInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(Response<void>(requestOptions: options, statusCode: 204));
  }
}

final class _DeleteErrorInterceptor extends Interceptor {
  _DeleteErrorInterceptor({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: statusCode,
          data: {'success': false, 'code': code, 'message': message},
        ),
      ),
      true,
    );
  }
}
