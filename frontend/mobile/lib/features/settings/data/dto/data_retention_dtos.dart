/// 데이터 보관 정책 3필드. 조회(GET)와 수정(PATCH) 응답이 같은 스키마다.
///
/// 수정 요청은 두 기간을 모두 보내는 **전체 교체**이고 `policyStatus`는 서버가
/// 조립 시 항상 채우는 파생값이라 요청 본문에는 넣지 않는다([toUpdateJson]).
///
/// 계약: `docs/api/data-retention-policy-contract.md`
/// (`GET`·`PATCH /users/me/data-retention`, S15P11B209-564·565)
final class DataRetentionPolicyDto {
  const DataRetentionPolicyDto({
    required this.retentionDays,
    required this.noticeDaysBefore,
    required this.policyStatus,
  });

  factory DataRetentionPolicyDto.fromJson(Map<String, dynamic> json) =>
      DataRetentionPolicyDto(
        retentionDays: (json['retentionDays'] as num).toInt(),
        noticeDaysBefore: (json['noticeDaysBefore'] as num).toInt(),
        // 계약 §5③: 어휘가 늘 수 있으므로 문자열 그대로 보관하고, 알 수 없는
        // 값이 와도 깨지지 않게 둔다. 화면은 [isProvisional]로만 분기한다.
        policyStatus: json['policyStatus'] as String? ?? '',
      );

  /// 데이터를 보관하는 기간(일).
  final int retentionDays;

  /// 보관 만료 며칠 전에 안내하는지(일).
  final int noticeDaysBefore;

  /// 보관 정책 수치의 확정 상태. 계약상 현재 항상 `PROVISIONAL`이며, 사용자가
  /// 값을 바꿔도 `CONFIRMED`가 되지 않는다(팀 차원 확정만 상태를 바꾼다).
  final String policyStatus;

  /// `PATCH` 요청 본문. 두 필드가 모두 필수인 전체 교체다(계약 §2).
  /// `policyStatus`는 저장 컬럼이 아니라 파생값이라 보내지 않는다.
  Map<String, dynamic> toUpdateJson() => {
    'retentionDays': retentionDays,
    'noticeDaysBefore': noticeDaysBefore,
  };

  /// 보관 기간 수치가 아직 확정 전(잠정)인지. 확정 전임을 화면에 알리는 데 쓴다.
  bool get isProvisional => policyStatus == 'PROVISIONAL';
}
