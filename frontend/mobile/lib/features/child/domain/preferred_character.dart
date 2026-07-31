const supportedPreferredCharacters = <String>{
  'BASE',
  'PRINCESS',
  'DINO',
  'OCTOPUS',
};

/// 이전 앱의 캐릭터 코드는 기본 도담이로 안전하게 호환한다.
String normalizePreferredCharacter(String? value) {
  if (value != null && supportedPreferredCharacters.contains(value)) {
    return value;
  }
  return 'BASE';
}
