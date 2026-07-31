import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/preferred_character.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('백엔드가 허용하는 캐릭터 코드는 그대로 유지한다', () {
    for (final code in supportedPreferredCharacters) {
      expect(normalizePreferredCharacter(code), code);
    }
  });

  test('이전 캐릭터 코드는 BASE로 변환한다', () {
    expect(normalizePreferredCharacter('BEAR'), 'BASE');
    expect(normalizePreferredCharacter('RABBIT'), 'BASE');
    expect(normalizePreferredCharacter(null), 'BASE');
  });

  test('등록 요청은 이전 캐릭터 코드를 전송하지 않는다', () {
    const request = CreateChildRequestDto(
      nickname: '민지',
      birthDate: '2020-03-02',
      relationshipType: 'MOTHER',
      preferredCharacter: 'BEAR',
      questionDifficulty: 'PRESCHOOL',
      responseModes: ['VOICE'],
    );

    expect(request.toJson()['preferredCharacter'], 'BASE');
  });

  test('수정 요청은 이전 캐릭터 코드를 전송하지 않는다', () {
    const request = UpdateChildRequestDto(preferredCharacter: 'FOX');

    expect(request.toJson()['preferredCharacter'], 'BASE');
  });
}
