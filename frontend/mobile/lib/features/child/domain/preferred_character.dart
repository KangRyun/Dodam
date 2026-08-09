/// 백엔드 `preferredCharacter`가 받아주는 코드 전체.
///
/// `DodamCostume`의 코드 집합과 정확히 같아야 한다(S15P11B209-866). 한쪽만
/// 넓히면 아이가 고른 새 캐릭터가 요청 직렬화 단계에서 `BASE`로 바뀌어 조용히
/// 사라진다 — 교차 검증은 `preferred_character_contract_test.dart`가 지킨다.
const supportedPreferredCharacters = <String>{
  'BASE',
  'PRINCESS',
  'DINO',
  'OCTOPUS',
  'EXPLORER',
  'RIBBON',
  'PRINCE',
};

/// 이전 앱의 캐릭터 코드는 기본 도담이로 안전하게 호환한다.
String normalizePreferredCharacter(String? value) {
  if (value != null && supportedPreferredCharacters.contains(value)) {
    return value;
  }
  return 'BASE';
}
