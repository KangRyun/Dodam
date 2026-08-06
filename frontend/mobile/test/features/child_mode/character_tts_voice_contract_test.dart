import 'package:dodam/features/child_mode/domain/dodam_costume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('선택 가능한 모든 캐릭터는 확정된 TTS 음성 코드를 가진다', () {
    expect(
      {for (final costume in DodamCostume.values) costume.code: costume.ttsVoice},
      {
        'BASE': 'FABLE',
        'PRINCESS': 'NOVA',
        'DINO': 'ASH',
        'OCTOPUS': 'BALLAD',
        'EXPLORER': 'VERSE',
        'RIBBON': 'SAGE',
        'PRINCE': 'ECHO',
      },
    );
  });
}
