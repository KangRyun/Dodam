import '../../domain/repositories/child_consent_repository.dart';
import '../dto/child_consent_dtos.dart';

/// 백엔드 미연결 개발 환경용 구현.
///
/// 약관을 비워 두면 등록 화면의 동의 섹션이 나타나지 않고, 제출도 하지 않는다.
final class MockChildConsentRepository implements ChildConsentRepository {
  const MockChildConsentRepository();

  @override
  Future<List<ConsentTermDto>> getChildTerms() async => const [];

  @override
  Future<void> submitChildConsents({
    required int childId,
    required List<ConsentAgreementDto> agreements,
  }) async {}
}
