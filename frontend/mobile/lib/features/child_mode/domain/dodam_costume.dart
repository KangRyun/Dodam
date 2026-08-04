/// 아동 홈에서 고를 수 있는 도담이 코스튬(S15P11B209-750).
///
/// 왼쪽 캐릭터 캐러셀에서 옆으로 넘겨 고른다. 백엔드 `preferredCharacter`는
/// 프로필의 `preferredCharacter`와 같은 코드를 사용하며, 기기 로컬 값은
/// 프로필을 아직 불러오지 못한 경우의 복원값으로 사용한다.
///
/// 새 코스튬은 반드시 목록 끝에 덧붙인다(S15P11B209-866의 3종 포함). 기존 항목의
/// 순서에 의존하는 테스트가 있어 중간 삽입은 무관한 케이스를 깨뜨린다. 코드를
/// 추가할 때는 서버로 나가는 허용 목록(`supportedPreferredCharacters`)도 같은
/// commit에서 함께 넓혀야 한다 — 빠뜨리면 PATCH가 조용히 `BASE`로 정규화된다.
enum DodamCostume {
  base('BASE', '도담이', 'assets/characters/costumes/dodam_base.png'),
  princess(
    'PRINCESS',
    '공주 도담이',
    'assets/characters/costumes/dodam_princess.png',
  ),
  dino('DINO', '공룡 도담이', 'assets/characters/costumes/dodam_dino.png'),
  octopus('OCTOPUS', '문어 도담이', 'assets/characters/costumes/dodam_octopus.png'),
  explorer(
    'EXPLORER',
    '탐험가 도담이',
    'assets/characters/costumes/dodami_explorer_profile.png',
  ),
  ribbon(
    'RIBBON',
    '리본 도담이',
    'assets/characters/costumes/dodami_ribbon_profile.png',
  ),
  prince(
    'PRINCE',
    '왕자 도담이',
    'assets/characters/costumes/dodami_prince_profile.png',
  );

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
