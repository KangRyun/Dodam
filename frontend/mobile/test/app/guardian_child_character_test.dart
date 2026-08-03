import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GuardianChildController.updateChildCharacter (S15P11B209-505)', () {
    test('고른 캐릭터를 목록에 즉시 반영하고 백엔드에 저장한다', () async {
      final repository = _FakeChildRepository([_child(3, 'BASE')]);
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren();

      await controller.updateChildCharacter(3, 'DINO');

      expect(controller.children.single.preferredCharacter, 'DINO');
      expect(repository.updateCalls.single.$1, 3);
      expect(repository.updateCalls.single.$2.preferredCharacter, 'DINO');
    });

    test('선택된 아동이면 selectedChild에도 반영한다', () async {
      final repository = _FakeChildRepository([_child(3, 'BASE')]);
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren(); // 첫 아동이 자동 선택된다

      await controller.updateChildCharacter(3, 'PRINCESS');

      expect(controller.selectedChild?.preferredCharacter, 'PRINCESS');
    });

    test('백엔드 저장이 실패해도 예외 없이 화면 값은 유지한다', () async {
      final repository = _FakeChildRepository(
        [_child(3, 'BASE')],
        updateError: StateError('network'),
      );
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren();

      await controller.updateChildCharacter(3, 'OCTOPUS');

      expect(controller.children.single.preferredCharacter, 'OCTOPUS');
    });

    test('같은 캐릭터면 목록을 바꾸지 않지만 저장은 시도한다', () async {
      final repository = _FakeChildRepository([_child(3, 'DINO')]);
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren();

      await controller.updateChildCharacter(3, 'DINO');

      expect(controller.children.single.preferredCharacter, 'DINO');
      // 같은 값이라도 배경 저장(best-effort)은 한 번 나간다.
      expect(repository.updateCalls, hasLength(1));
    });
  });
}

ChildSummaryDto _child(int id, String character) => ChildSummaryDto(
  childId: id,
  nickname: 'child$id',
  birthDate: '2019-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: character,
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'COMPLETED',
  relationshipType: 'MOTHER',
  recentActivity: const ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

ChildDetailDto _detail(int id, String character) => ChildDetailDto(
  childId: id,
  nickname: 'child$id',
  birthDate: '2019-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: character,
  questionDifficulty: 'PRESCHOOL',
  responseModes: const ['VOICE'],
  tutorialStatus: 'COMPLETED',
  profileStatus: 'ACTIVE',
  relationshipType: 'MOTHER',
  createdAt: null,
);

final class _FakeChildRepository implements ChildRepository {
  _FakeChildRepository(this.children, {this.updateError});

  List<ChildSummaryDto> children;
  Object? updateError;
  final List<(int, UpdateChildRequestDto)> updateCalls = [];

  @override
  Future<List<ChildSummaryDto>> getChildren() async => children;

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) async {
    updateCalls.add((childId, request));
    if (updateError != null) throw updateError!;
    return _detail(childId, request.preferredCharacter ?? 'BASE');
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();

  @override
  Future<void> deleteChild(int childId) => throw UnimplementedError();

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
