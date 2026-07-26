import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 타이포그래피 디자인 토큰 (S15P11B209-434).
///
/// ⚠️ 골격(skeleton) 단계 — 2026-07-26.
/// - 이 파일은 텍스트 스타일의 **이름(API)** 을 확정한다. 값(크기·굵기·폰트)은
///   현재 화면/컴포넌트에서 쓰던 값을 임시로 옮겨둔 것이며, 다음 주 새 디자인이
///   확정되면 **이 파일에서 값만** 교체한다(참조하는 컴포넌트는 수정 불필요).
/// - 폰트(Do Hyeon·IBM Plex)는 아직 pubspec에 번들되지 않았다. [AppFontFamily]
///   이름은 미리 지정해 두었고, 번들 전까지는 플랫폼 기본 폰트로 대체 렌더링된다
///   (현재 동작과 동일). 폰트 파일 추가·pubspec 연결은 별도 작업.
/// - 이름은 의미 기반(titleLg·body·label…)이라 값이 바뀌어도 뜻이 유지된다.
abstract final class AppFontFamily {
  /// 제목·버튼 — Do Hyeon (CLAUDE.md §8). pubspec 번들 시 family명 일치 필요.
  static const String display = 'DoHyeon';

  /// 본문 — IBM Plex Sans KR.
  static const String body = 'IBMPlexSansKR';

  /// 라벨·수치 — IBM Plex Mono.
  static const String mono = 'IBMPlexMono';
}

/// 앱 전역 텍스트 스타일 토큰.
///
/// 컴포넌트·화면은 `TextStyle`을 직접 만들지 말고 이 상수를 참조한다
/// (색상 [AppColors]·간격 [AppSpacing]과 동일한 사용 패턴).
/// 예) `Text(title, style: AppTypography.titleLg)`
abstract final class AppTypography {
  // ── 제목 (Do Hyeon) ────────────────────────────────────────────────
  /// 큰 제목 — 다이얼로그 제목·주요 화면 헤딩. (현행 22/w800)
  static const TextStyle titleLg = TextStyle(
    fontFamily: AppFontFamily.display,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.3,
    color: AppColors.ink,
  );

  /// 중간 제목 — 섹션 헤딩.
  static const TextStyle titleMd = TextStyle(
    fontFamily: AppFontFamily.display,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.ink,
  );

  // ── 본문 (IBM Plex Sans KR) ────────────────────────────────────────
  /// 기본 본문. (현행 16/w400)
  static const TextStyle body = TextStyle(
    fontFamily: AppFontFamily.body,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.ink,
  );

  /// 강조 본문 — 선택 항목 라벨 등. (현행 16/w600)
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: AppFontFamily.body,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.ink,
  );

  /// 보조 설명·도움말. (현행 14, inkMuted)
  static const TextStyle bodySm = TextStyle(
    fontFamily: AppFontFamily.body,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.inkMuted,
  );

  // ── 버튼 (Do Hyeon) ────────────────────────────────────────────────
  /// 버튼 라벨. (현행 15~16/w600~700)
  static const TextStyle button = TextStyle(
    fontFamily: AppFontFamily.display,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  // ── 라벨·수치 (IBM Plex Mono) ──────────────────────────────────────
  /// 라벨·수치·상태 배지 텍스트. (§8: 모노)
  static const TextStyle label = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: AppColors.inkMuted,
  );

  /// 가장 작은 캡션. (현행 12~13)
  static const TextStyle caption = TextStyle(
    fontFamily: AppFontFamily.body,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.inkMuted,
  );
}
