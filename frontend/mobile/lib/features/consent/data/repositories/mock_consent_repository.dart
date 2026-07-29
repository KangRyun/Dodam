import '../../../child/data/dto/child_consent_dtos.dart';
import '../../domain/repositories/consent_repository.dart';
import '../dto/consent_status_dtos.dart';

/// 백엔드 미연결 개발·테스트용 동의 현황. 필수/선택과 동의 상태 조합을 담는다.
final class MockConsentRepository implements ConsentRepository {
  const MockConsentRepository();

  static const _userTerms = [
    ConsentTermDto(
      termId: 1,
      termCode: 'SERVICE_TERMS',
      title: '서비스 이용약관',
      required: true,
      version: 'v1',
    ),
    ConsentTermDto(
      termId: 2,
      termCode: 'PRIVACY',
      title: '개인정보 수집·이용',
      required: true,
      version: 'v1',
    ),
    ConsentTermDto(
      termId: 3,
      termCode: 'MARKETING',
      title: '마케팅 정보 수신',
      required: false,
      version: 'v1',
    ),
  ];

  static const _childTerms = [
    ConsentTermDto(
      termId: 11,
      termCode: 'CHILD_DATA',
      title: '아동 데이터 처리',
      required: true,
      version: 'v1',
    ),
    ConsentTermDto(
      termId: 12,
      termCode: 'VOICE',
      title: '음성 데이터 처리',
      required: false,
      version: 'v1',
    ),
  ];

  static const _userItems = [
    ConsentStatusItemDto(
      termId: 1,
      termCode: 'SERVICE_TERMS',
      required: true,
      version: 'v1',
      agreed: true,
    ),
    ConsentStatusItemDto(
      termId: 2,
      termCode: 'PRIVACY',
      required: true,
      version: 'v1',
      agreed: true,
    ),
    ConsentStatusItemDto(
      termId: 3,
      termCode: 'MARKETING',
      required: false,
      version: 'v1',
      agreed: true,
    ),
  ];

  static const _childItems = [
    ConsentStatusItemDto(
      termId: 11,
      termCode: 'CHILD_DATA',
      required: true,
      version: 'v1',
      agreed: true,
    ),
    ConsentStatusItemDto(
      termId: 12,
      termCode: 'VOICE',
      required: false,
      version: 'v1',
      agreed: false,
    ),
  ];

  @override
  Future<List<ConsentTermDto>> getTerms(ConsentTargetScope scope) async =>
      scope == ConsentTargetScope.child ? _childTerms : _userTerms;

  @override
  Future<ConsentStatusDto> getStatus({int? childId}) async => childId == null
      ? const ConsentStatusDto(
          requiredConsentsSatisfied: true,
          items: _userItems,
        )
      : ConsentStatusDto(
          childId: childId,
          requiredConsentsSatisfied: true,
          items: _childItems,
        );

  @override
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  }) async {}
}
