import '../../domain/repositories/child_repository.dart';
import '../dto/child_dtos.dart';

final class MockChildRepository implements ChildRepository {
  const MockChildRepository();
  static const _child = {
    'childId': 3,
    'nickname': '도담이',
    'birthDate': '2019-03-14',
    'age': 7,
    'profileImageUrl': null,
    'preferredCharacter': 'BASE',
    'questionDifficulty': 'PRESCHOOL',
    'responseModes': ['VOICE', 'OPTION'],
    'tutorialStatus': 'NOT_STARTED',
    'profileStatus': 'ACTIVE',
    'relationshipType': 'MOTHER',
    'createdAt': '2026-07-21T09:30:00Z',
    'updatedAt': '2026-07-21T09:30:00Z',
  };

  @override
  Future<List<ChildSummaryDto>> getChildren() async => [
    ChildSummaryDto.fromJson({
      ..._child,
      'recentActivity': {
        'lastActivityAt': '2026-07-20T08:15:00Z',
        'totalActivityCount': 12,
      },
    }),
  ];
  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async =>
      ChildDetailDto.fromJson(_child);
  @override
  Future<ChildDetailDto> getChild(int childId) async =>
      ChildDetailDto.fromJson(_child);
  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) async =>
      ChildDetailDto.fromJson({..._child, 'updatedAt': '2026-07-21T09:31:00Z'});
  @override
  Future<void> deleteChild(int childId) async {}
  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) async =>
      TutorialProgressDto.fromJson(const {
        'childId': 3,
        'tutorialStatus': 'IN_PROGRESS',
        'lastStep': 'ERASER',
        'completedAt': null,
        'updatedAt': '2026-07-20T08:02:00Z',
      });
  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) async => TutorialProgressDto.fromJson(const {
    'childId': 3,
    'tutorialStatus': 'COMPLETED',
    'lastStep': 'OPTION_CHIP',
    'completedAt': '2026-07-21T09:34:00Z',
    'updatedAt': '2026-07-21T09:34:00Z',
  });
}
