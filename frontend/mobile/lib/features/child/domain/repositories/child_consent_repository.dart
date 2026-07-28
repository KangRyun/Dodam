import '../../data/dto/child_consent_dtos.dart';

/// 아동 대상(CHILD) 약관 조회와 동의 이력 기록 경계.
///
/// 보호자 온보딩은 USER 범위 약관만 다루므로, 아동 데이터(음성·그림 분석 등)에 관한
/// 동의는 아동 등록 시점에 이 경계로 따로 기록해야 한다. 이 기록이 없으면 서버가
/// 음성 답변을 `403 VOICE_CONSENT_REQUIRED`로 거절한다.
abstract interface class ChildConsentRepository {
  /// 현재 시행 중인 아동 대상 약관 목록을 조회한다.
  Future<List<ConsentTermDto>> getChildTerms();

  /// 아동 한 명에 대한 약관 동의·철회 이력을 일괄 기록한다.
  Future<void> submitChildConsents({
    required int childId,
    required List<ConsentAgreementDto> agreements,
  });
}
