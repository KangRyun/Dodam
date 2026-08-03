/// 아동 홈에서 고를 수 있는 도담이 코스튬(S15P11B209-750).
///
/// 왼쪽 캐릭터 캐러셀에서 옆으로 넘겨 고른다. 백엔드 `preferredCharacter`는
/// 프로필의 `preferredCharacter`와 같은 코드를 사용하며, 기기 로컬 값은
/// 프로필을 아직 불러오지 못한 경우의 복원값으로 사용한다.
enum DodamCostume {
  base('BASE', '도담이', 'assets/characters/costumes/dodam_base.png'),
  princess(
    'PRINCESS',
    '공주 도담이',
    'assets/characters/costumes/dodam_princess.png',
  ),
  dino('DINO', '공룡 도담이', 'assets/characters/costumes/dodam_dino.png'),
  octopus('OCTOPUS', '문어 도담이', 'assets/characters/costumes/dodam_octopus.png');

  const DodamCostume(this.code, this.label, this.asset);

  /// 로컬 저장·복원용 코드.
  final String code;

  /// 캐릭터 이름 라벨(예: "공주 도담이").
  final String label;

  /// 캐릭터 이미지 에셋 경로.
  final String asset;

  /// 저장된 코드로 코스튬을 복원한다. 알 수 없는 값은 기본 도담이로 대체한다.
  static DodamCostume fromCode(String? code) => values.firstWhere(
    (costume) => costume.code == code,
    orElse: () => DodamCostume.base,
  );
}
