import '../../../child/data/dto/child_consent_dtos.dart';
import '../../data/dto/consent_status_dtos.dart';

/// 동의 약관의 적용 범위. 보호자 본인([user])과 아동 대상([child])을 구분한다.
enum ConsentTargetScope {
  user('USER'),
  child('CHILD');

  const ConsentTargetScope(this.wire);

  /// 서버 쿼리 파라미터 값.
  final String wire;
}

/// 동의 현황 조회·변경(설정 > 동의 관리).
///
/// 보호자 본인 동의는 [childId]를 비우고, 아동 동의는 아동 [childId]로 대상을
/// 구분한다. 하나의 화면에서 대상만 바꿔 재사용한다.
abstract interface class ConsentRepository {
  /// 적용 범위의 활성 약관 목록(제목·필수여부 표시용).
  Future<List<ConsentTermDto>> getTerms(ConsentTargetScope scope);

  /// 현재 동의 현황. [childId]가 있으면 그 아동 범위.
  Future<ConsentStatusDto> getStatus({int? childId});

  /// 선택 약관의 동의/철회 변경(append-only 이력). 필수 약관은 대상이 아니다.
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  });
}
