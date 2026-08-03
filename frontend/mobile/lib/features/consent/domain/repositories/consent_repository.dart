import '../../../child/data/dto/child_consent_dtos.dart';
import '../../data/dto/consent_status_dtos.dart';
import '../enums/consent_target_scope.dart';

export '../enums/consent_target_scope.dart';

/// 동의 현황 조회·변경(설정 > 동의 관리)과 약관 목록 조회(설정 > 약관 및 정책).
///
/// 보호자 본인 동의는 [ConsentRepository.getStatus]의 `childId`를 비우고, 아동
/// 동의는 아동 `childId`로 대상을 구분한다. 하나의 화면에서 대상만 바꿔 재사용한다.
abstract interface class ConsentRepository {
  /// 현재 시행 중인 활성 약관 목록(제목·필수여부·원문 표시용).
  ///
  /// [scope]를 주지 않으면 전 범위(USER + CHILD)를 한 번에 받는다. 서버가
  /// `targetScope` Query를 선택값으로 두고 없으면 필터를 걸지 않기 때문이다
  /// (`ConsentTermQueryService.getActiveTerms`). 약관 열람 화면은 아동을 고르지
  /// 않고도 전 범위를 보여줘야 해서 이 형태를 쓴다.
  Future<List<ConsentTermDto>> getTerms([ConsentTargetScope? scope]);

  /// 현재 동의 현황. [childId]가 있으면 그 아동 범위.
  Future<ConsentStatusDto> getStatus({int? childId});

  /// 선택 약관의 동의/철회 변경(append-only 이력). 필수 약관은 대상이 아니다.
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  });
}
