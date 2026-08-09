import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/consent/data/dto/consent_status_dtos.dart';
import 'package:dodam/features/consent/domain/repositories/consent_repository.dart';
import 'package:dodam/features/consent/presentation/controllers/consent_management_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsentManagementController', () {
    test('약관과 현황을 조인해 표시 모델(제목·필수·동의)을 만든다', () async {
      final repository = _FakeConsentRepository(
        userTerms: const [
          ConsentTermDto(
            termId: 1,
            termCode: 'SERVICE_TERMS',
            title: '서비스 이용약관',
            required: true,
            version: 'v1',
          ),
          ConsentTermDto(
            termId: 3,
            termCode: 'MARKETING',
            title: '마케팅 수신',
            required: false,
            version: 'v1',
          ),
        ],
        userAgreed: {1: true, 3: true},
      );
      final controller = ConsentManagementController(repository);

      await controller.loadGuardian();

      expect(controller.guardianStatus, ConsentSectionStatus.ready);
      expect(
        controller.guardianConsents.map((item) => item.title),
        ['서비스 이용약관', '마케팅 수신'],
      );
      expect(controller.guardianConsents[0].required, isTrue);
      expect(controller.guardianConsents[1].required, isFalse);
      expect(controller.guardianConsents[1].agreed, isTrue);
    });

    test('선택 약관 철회는 WITHDRAW를 보내고 현황을 갱신한다', () async {
      final repository = _FakeConsentRepository(
        userTerms: const [
          ConsentTermDto(
            termId: 3,
            termCode: 'MARKETING',
            title: '마케팅 수신',
            required: false,
            version: 'v1',
          ),
        ],
        userAgreed: {3: true},
      );
      final controller = ConsentManagementController(repository);
      await controller.loadGuardian();

      final ok = await controller.setAgreed(termId: 3, agreed: false);

      expect(ok, isTrue);
      expect(repository.lastChildId, isNull);
      expect(repository.lastAgreements.single.termId, 3);
      expect(repository.lastAgreements.single.action, 'WITHDRAW');
      // 철회 후 현황을 다시 조회해 반영한다.
      expect(controller.guardianConsents.single.agreed, isFalse);
    });

    test('아동을 선택하면 그 아동 childId로 현황을 조회한다', () async {
      final repository = _FakeConsentRepository(
        childTerms: const [
          ConsentTermDto(
            termId: 12,
            termCode: 'VOICE',
            title: '음성 처리',
            required: false,
            version: 'v1',
          ),
        ],
        childAgreed: {12: false},
      );
      final controller = ConsentManagementController(repository);

      await controller.selectChild(7);

      expect(controller.selectedChildId, 7);
      expect(repository.lastStatusChildId, 7);
      expect(controller.childConsents.single.title, '음성 처리');
      expect(controller.childConsents.single.agreed, isFalse);
    });
  });
}

final class _FakeConsentRepository implements ConsentRepository {
  _FakeConsentRepository({
    this.userTerms = const [],
    this.childTerms = const [],
    Map<int, bool>? userAgreed,
    Map<int, bool>? childAgreed,
  }) : _userAgreed = {...?userAgreed},
       _childAgreed = {...?childAgreed};

  final List<ConsentTermDto> userTerms;
  final List<ConsentTermDto> childTerms;
  final Map<int, bool> _userAgreed;
  final Map<int, bool> _childAgreed;

  List<ConsentAgreementDto> lastAgreements = const [];
  int? lastChildId;
  int? lastStatusChildId;

  @override
  Future<List<ConsentTermDto>> getTerms([ConsentTargetScope? scope]) async =>
      scope == ConsentTargetScope.child ? childTerms : userTerms;

  @override
  Future<ConsentStatusDto> getStatus({int? childId}) async {
    lastStatusChildId = childId;
    final agreed = childId == null ? _userAgreed : _childAgreed;
    return ConsentStatusDto(
      childId: childId,
      requiredConsentsSatisfied: true,
      items: [
        for (final entry in agreed.entries)
          ConsentStatusItemDto(
            termId: entry.key,
            termCode: 'T${entry.key}',
            required: false,
            version: 'v1',
            agreed: entry.value,
          ),
      ],
    );
  }

  @override
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  }) async {
    lastChildId = childId;
    lastAgreements = agreements;
    final target = childId == null ? _userAgreed : _childAgreed;
    for (final agreement in agreements) {
      target[agreement.termId] = agreement.action == 'AGREE';
    }
  }
}
