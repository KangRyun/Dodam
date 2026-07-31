import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_consent_repository.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('아동 등록 직후 선택한 아동 동의를 함께 기록한다', () async {
    final consentRepository = _FakeChildConsentRepository();
    final controller = GuardianChildController(
      _FakeChildRepository(),
      consentRepository,
    );
    addTearDown(controller.dispose);

    final registered = await controller.registerChild(
      _request,
      consentAgreements: const [
        ConsentAgreementDto.agree(11),
        ConsentAgreementDto.withdraw(12),
      ],
    );

    expect(registered, isTrue);
    expect(consentRepository.childIds, [77]);
    expect(consentRepository.submitted.single.map((item) => item.toJson()), [
      {'termId': 11, 'action': 'AGREE'},
      {'termId': 12, 'action': 'WITHDRAW'},
    ]);
    expect(controller.consentRecordError, isNull);
  });

  test('동의 기록이 실패해도 아동 등록은 유지하고 원인을 남긴다', () async {
    final consentRepository = _FakeChildConsentRepository(
      error: Exception('consent down'),
    );
    final controller = GuardianChildController(
      _FakeChildRepository(),
      consentRepository,
    );
    addTearDown(controller.dispose);

    final registered = await controller.registerChild(
      _request,
      consentAgreements: const [ConsentAgreementDto.agree(11)],
    );

    // 아동 데이터를 되돌리는 편이 더 위험하므로 등록은 성공으로 둔다.
    expect(registered, isTrue);
    expect(controller.registrationStatus, ChildRegistrationStatus.success);
    expect(controller.consentRecordError, isNotNull);
  });

  test('동의할 약관이 없으면 동의 API를 호출하지 않는다', () async {
    final consentRepository = _FakeChildConsentRepository();
    final controller = GuardianChildController(
      _FakeChildRepository(),
      consentRepository,
    );
    addTearDown(controller.dispose);

    await controller.registerChild(_request);

    expect(consentRepository.submitted, isEmpty);
  });

  test('약관 조회가 실패하면 빈 목록으로 두어 등록 화면을 막지 않는다', () async {
    final controller = GuardianChildController(
      _FakeChildRepository(),
      _FakeChildConsentRepository(termsError: Exception('terms down')),
    );
    addTearDown(controller.dispose);

    await controller.loadChildConsentTerms();

    expect(controller.childConsentTerms, isEmpty);
  });

  test('아동 수정 후 최신 목록을 다시 조회한다', () async {
    final repository = _FakeChildRepository();
    final controller = GuardianChildController(repository);
    addTearDown(controller.dispose);

    final updated = await controller.updateChild(
      77,
      const UpdateChildRequestDto(
        nickname: '민지 수정',
        preferredCharacter: 'OCTOPUS',
        questionDifficulty: 'LOWER_ELEMENTARY',
      ),
    );

    expect(updated, isTrue);
    expect(repository.updatedChildIds, [77]);
    expect(repository.getChildrenCallCount, 1);
  });

  test('아동 삭제 후 최신 목록을 다시 조회한다', () async {
    final repository = _FakeChildRepository();
    final controller = GuardianChildController(repository);
    addTearDown(controller.dispose);

    final deleted = await controller.deleteChild(77);

    expect(deleted, isTrue);
    expect(repository.deletedChildIds, [77]);
    expect(repository.getChildrenCallCount, 1);
  });
}

const _request = CreateChildRequestDto(
  nickname: '민지',
  birthDate: '2020-03-02',
  relationshipType: 'MOTHER',
  preferredCharacter: 'BASE',
  questionDifficulty: 'PRESCHOOL',
  responseModes: ['VOICE'],
);

final class _FakeChildConsentRepository implements ChildConsentRepository {
  _FakeChildConsentRepository({this.error, this.termsError});

  final Object? error;
  final Object? termsError;
  final List<int> childIds = [];
  final List<List<ConsentAgreementDto>> submitted = [];

  @override
  Future<List<ConsentTermDto>> getChildTerms() async {
    if (termsError != null) throw termsError!;
    return const [
      ConsentTermDto(
        termId: 11,
        termCode: 'VOICE_PROCESSING',
        title: '음성 데이터 처리',
        required: false,
        version: 'v1',
      ),
    ];
  }

  @override
  Future<void> submitChildConsents({
    required int childId,
    required List<ConsentAgreementDto> agreements,
  }) async {
    childIds.add(childId);
    submitted.add(agreements);
    if (error != null) throw error!;
  }
}

final class _FakeChildRepository implements ChildRepository {
  final List<int> updatedChildIds = [];
  final List<int> deletedChildIds = [];
  int getChildrenCallCount = 0;

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async =>
      _detail;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCallCount += 1;
    return const [_summary];
  }

  @override
  Future<ChildDetailDto> getChild(int childId) async => _detail;

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) async {
    updatedChildIds.add(childId);
    return _detail;
  }

  @override
  Future<void> deleteChild(int childId) async {
    deletedChildIds.add(childId);
  }

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

const _detail = ChildDetailDto(
  childId: 77,
  nickname: '민지',
  birthDate: '2020-03-02',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: 'BASE',
  questionDifficulty: 'PRESCHOOL',
  responseModes: ['VOICE'],
  tutorialStatus: 'NOT_STARTED',
  profileStatus: 'ACTIVE',
  relationshipType: 'MOTHER',
  createdAt: '2026-07-28T09:00:00',
);

const _summary = ChildSummaryDto(
  childId: 77,
  nickname: '민지',
  birthDate: '2020-03-02',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: 'BASE',
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'NOT_STARTED',
  relationshipType: 'MOTHER',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);
