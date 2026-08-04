import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/preferred_character.dart';
import 'package:dodam/features/child_mode/domain/dodam_costume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('백엔드가 허용하는 캐릭터 코드는 그대로 유지한다', () {
    for (final code in supportedPreferredCharacters) {
      expect(normalizePreferredCharacter(code), code);
    }
  });

  /// 캐러셀에 코스튬만 추가하고 이 Set을 빠뜨리면 요청 직렬화가 새 코드를 조용히
  /// `BASE`로 바꿔 아이의 선택이 사라진다(S15P11B209-866).
  test('캐러셀 코스튬 코드와 서버 허용 목록은 정확히 일치한다', () {
    expect(
      DodamCostume.values.map((costume) => costume.code).toSet(),
      supportedPreferredCharacters,
    );
  });

  test('지원 캐릭터는 기존 4종과 신규 3종을 합친 7종이다', () {
    expect(supportedPreferredCharacters, hasLength(7));
    expect(supportedPreferredCharacters, {
      'BASE',
      'PRINCESS',
      'DINO',
      'OCTOPUS',
      'EXPLORER',
      'RIBBON',
      'PRINCE',
    });
  });

  test('신규 3종은 수정 요청 직렬화에서 그대로 전송된다', () {
    for (final code in ['EXPLORER', 'RIBBON', 'PRINCE']) {
      expect(
        UpdateChildRequestDto(
          preferredCharacter: code,
        ).toJson()['preferredCharacter'],
        code,
      );
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
