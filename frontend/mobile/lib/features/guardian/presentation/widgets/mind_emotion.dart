import 'package:flutter/material.dart';

/// 마음 달력에 쓰는 감정 종류. API `EmotionType`(HAPPY·SAD·ANGRY·SCARED·CALM) 중
/// 표시 대상만 담는다. `UNKNOWN`은 감정 선택에서 받지 않기로 해(제품 규칙) 매핑하지
/// 않으며, 매핑되지 않는 값은 "기록 없음"으로 취급한다.
enum MindEmotion {
  happy(
    label: '기쁨',
    asset: 'assets/characters/emotions/dodam_emotion_joy.png',
    background: Color(0xFFFBEBA0),
  ),
  calm(
    label: '편안',
    asset: 'assets/characters/emotions/dodam_emotion_calm.png',
    background: Color(0xFFCDE7D2),
  ),
  sad(
    label: '슬픔',
    asset: 'assets/characters/emotions/dodam_emotion_sad.png',
    background: Color(0xFFCDDCF3),
  ),
  angry(
    label: '화남',
    asset: 'assets/characters/emotions/dodam_emotion_angry.png',
    background: Color(0xFFF6C7BC),
  ),
  scared(
    label: '불안',
    asset: 'assets/characters/emotions/dodam_emotion_anxious.png',
    background: Color(0xFFE0D5F1),
  );

  const MindEmotion({
    required this.label,
    required this.asset,
    required this.background,
  });

  final String label;
  final String asset;
  final Color background;

  /// API가 내려주는 감정 문자열을 표시용 [MindEmotion]으로 바꾼다. 표시 대상이
  /// 아닌 값(`UNKNOWN`·미지정 등)은 null을 돌려주고 호출자는 "기록 없음"으로 그린다.
  static MindEmotion? fromApi(String? raw) => switch (raw) {
    'HAPPY' || 'JOY' => MindEmotion.happy,
    'CALM' => MindEmotion.calm,
    'SAD' => MindEmotion.sad,
    'ANGRY' => MindEmotion.angry,
    'SCARED' => MindEmotion.scared,
    _ => null,
  };
}
