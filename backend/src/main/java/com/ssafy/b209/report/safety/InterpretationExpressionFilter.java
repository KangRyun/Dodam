package com.ssafy.b209.report.safety;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * 안전 검증 <strong>2단 — 표현 안전 필터</strong>다(보호자 계약 §4-3, 875 계약 §4-2).
 *
 * <p>실패하면 <strong>EXPERT_ONLY 강등 + {@code expertReviewRequired=true}</strong>이며 <strong>내용은
 * 보존</strong>한다. 1단(구조적 공개 게이트) 실패와 달리 근거는 갖췄고 표현만 문제인 경우이므로, 폐기하지 않고 전문가가 검토할 수 있게 격리한다.
 *
 * <p><strong>기준은 AI 측 {@code ai/report_safety.py}(S15P11B209-591·592 확정)를 그대로 이식했다.</strong> 갈리면
 * 통과·차단이 엇갈리므로 패턴을 임의로 손보지 않는다. 두 부류를 잡는다.
 *
 * <ol>
 *   <li>단정적 진단 — 임상 장애·질환명, "진단됩니다/~장애입니다" 단정, 확정 부사 + 부정 해석, "이 그림은 ~를 의미합니다"류 확정적 해석
 *   <li>감정·성격 과잉 추론 — 성향·기질·정체성을 고정 특질로 규정, 심리 속성 단정
 * </ol>
 *
 * <p>허용: "~일 수 있어요" · "~한 경향" · "~한 모습을 보였어요"(행동 관찰) 같은 여지·관찰 표현.
 *
 * <p><strong>주의 — "여기서 허용"이 "공개된다"는 뜻은 아니다.</strong> 위 허용 예는 계약이 <em>이 필터(2단)의 기준</em>으로 든
 * 것이다({@code docs/api/report-detail-guardian-contract.md:115} · {@code
 * docs/S15P11B209-875-report-api-contract.md:174}). "강등하지 말라"는 뜻이고 "가능성 어조로 인정하라"는 뜻이 아니다.
 *
 * <p>가능성 어조는 <strong>별개의 1단 조건</strong>이다 — 875 §4-1 조건 4와 같은 문서 {@code :108}("{@code
 * tendencyText}는 반드시 가능성 어조"). 그래서 "~한 모습을 보였어요"만으로 된 {@code tendencyText}는 <em>이 필터는 통과하지만 1단 어조
 * 검사에서 탈락</em>하며, 그 두 결과가 동시에 계약을 만족한다. AI도 같은 구조다({@code report_safety.py}는 강등하지 않고, {@code
 * report_client.py}의 {@code _TENTATIVE_MARKERS}는 표지가 없다며 카드를 버린다). 표지 목록은 {@link
 * InterpretationPublicationGate} 참고.
 *
 * <p><strong>가드레일:</strong> 매칭 결과로 패턴만 돌려주고 원문은 돌려주지 않는다 — 카드 문장에 아이 표현이 섞일 수 있다.
 *
 * <p>정규식은 {@link Pattern#UNICODE_CHARACTER_CLASS}로 컴파일한다. Java의 {@code \s} 기본값은 ASCII 공백만 잡지만
 * Python {@code re}는 유니코드 공백까지 잡으므로, 이 플래그가 없으면 전각 공백 같은 입력에서 두 구현의 판정이 갈린다.
 */
public final class InterpretationExpressionFilter {

  private static final int FLAGS = Pattern.UNICODE_CHARACTER_CLASS;

  /** 임상 장애·질환명. 여지 표현과 무관하게 보호자 화면에 바로 나가면 안 된다. */
  private static final List<String> DISORDER_TERMS =
      List.of(
          "우울\\s*증",
          "우울\\s*장애",
          "불안\\s*장애",
          "공황\\s*장애",
          "조현병",
          "자폐(\\s*스펙트럼)?",
          "아스퍼거",
          "ADHD",
          "에이디에이치디",
          "주의력\\s*결핍",
          "과잉\\s*행동\\s*장애",
          "틱\\s*장애",
          "강박\\s*장애",
          "외상\\s*후\\s*스트레스",
          "PTSD",
          "품행\\s*장애",
          "반항\\s*장애",
          "애착\\s*장애",
          "분리\\s*불안\\s*장애",
          "발달\\s*장애",
          "지적\\s*장애",
          "학습\\s*장애",
          "경계선\\s*(지능|성격)",
          "인격\\s*장애",
          "성격\\s*장애",
          "정신\\s*(질환|장애|병)",
          "신경증",
          "병리적");

  /** 진단 단정 프레이밍. 여지 어미("~수 있어요")는 걸리지 않는다. */
  private static final List<String> ASSERTION_PATTERNS =
      List.of(
          "진단(됩니다|된다|입니다|이에요|받아야|이\\s*필요)",
          "(으로|로)\\s*진단",
          "(확실히|분명히|틀림없이|명백히|반드시)\\s*.{0,20}(불안|우울|공격|문제|장애|이상|위험)",
          "(불안정|공격적|산만|위축|우울|불안|위험)(합니다|합니까|입니다|이다)",
          "(이\\s*그림은|이\\s*아(이|동)는)\\s*.{0,20}(의미(합니다|한다|해요|이다|하는)|"
              + "나타(냅니다|낸다|내요)|상징(합니다|한다|해요)|드러(냅니다|낸다))");

  /** 낙인이 될 수 있는 우려 방향 특질어. 긍정·중립 관찰까지 막지 않으려 우려 특질로 좁힌다. */
  private static final String TRAIT_ADJ =
      "소심|내성적|소극적|공격적|폭력적|예민|민감|산만|충동적|위축|반항적|의존적|" + "이기적|자기중심적|냉담|무기력|강박적|비관적|우울|불안|외로|고집";

  /** 감정·성격 과잉 추론(고정 특질 규정). 행동 관찰·여지 표현은 종결 어미가 달라 걸리지 않는다. */
  private static final List<String> OVERINFERENCE_PATTERNS =
      List.of(
          "(" + TRAIT_ADJ + ")\\s*(합니다|합니까|해요|하다|입니다|이에요|예요|이다|이야)",
          "(성향|기질|인격|천성|본성)(이|은|는|을|이라)?.{0,4}"
              + "(입니다|이에요|예요|이다|있습니다|있어요|을\\s*가지|이\\s*강하|이\\s*뚜렷|을\\s*보인다)",
          "(" + TRAIT_ADJ + ")(한|인)\\s*아(이|동)\\s*(입니다|이에요|예요|이다|이야)",
          "(자존감|자신감|공감\\s*능력|사회성|자기\\s*조절|감정\\s*조절|자아|애착)"
              + "(이|은|는|력)?.{0,4}(낮습니다|낮아요|부족합니다|부족해요|없습니다|없어요|떨어집니다|떨어져요)",
          "애정\\s*결핍");

  private static final List<Pattern> DEFINITIVE_COMPILED = compile(allDefinitivePatterns());
  private static final List<Pattern> OVERINFERENCE_COMPILED = compile(OVERINFERENCE_PATTERNS);

  /** 상태 없는 필터다. */
  public InterpretationExpressionFilter() {}

  /**
   * 카드에 실린 문장을 모두 검사한다.
   *
   * @param candidate 검사할 경향 해석 카드
   * @return 검사 결과이며 매칭된 패턴만 담고 원문은 담지 않는다
   */
  public ExpressionVerdict inspect(InterpretationCandidate candidate) {
    List<String> matched = new ArrayList<>();
    for (String text : candidate.reviewableTexts()) {
      for (String pattern : findUnsafeExpression(text)) {
        if (!matched.contains(pattern)) {
          matched.add(pattern);
        }
      }
    }
    return new ExpressionVerdict(matched.isEmpty(), List.copyOf(matched));
  }

  /**
   * 단정적 진단 표현을 찾아 매칭된 패턴 목록을 돌려준다.
   *
   * @param text 검사할 문장이며 없으면 {@code null}
   * @return 매칭된 패턴 문자열 목록이며 없으면 빈 목록
   */
  public List<String> findDefinitiveDiagnosis(String text) {
    return match(DEFINITIVE_COMPILED, text);
  }

  /**
   * 감정·성격 과잉 추론 표현을 찾아 매칭된 패턴 목록을 돌려준다.
   *
   * @param text 검사할 문장이며 없으면 {@code null}
   * @return 매칭된 패턴 문자열 목록이며 없으면 빈 목록
   */
  public List<String> findOverinference(String text) {
    return match(OVERINFERENCE_COMPILED, text);
  }

  /**
   * 격리해야 할 표현(단정 진단 + 과잉 추론)을 함께 찾는다.
   *
   * @param text 검사할 문장이며 없으면 {@code null}
   * @return 매칭된 패턴 문자열 목록이며 없으면 빈 목록
   */
  public List<String> findUnsafeExpression(String text) {
    List<String> matched = new ArrayList<>(findDefinitiveDiagnosis(text));
    matched.addAll(findOverinference(text));
    return List.copyOf(matched);
  }

  /**
   * 주어진 문장 중 하나라도 격리 대상 표현을 담는지 판정한다.
   *
   * @param texts 검사할 문장들
   * @return 하나라도 격리 대상 표현을 담으면 {@code true}
   */
  public boolean hasUnsafeExpression(String... texts) {
    for (String text : texts) {
      if (!findUnsafeExpression(text).isEmpty()) {
        return true;
      }
    }
    return false;
  }

  /**
   * 단정적 진단 패턴 문자열 전체를 돌려준다.
   *
   * @return 패턴 문자열 목록
   */
  static List<String> allDefinitivePatterns() {
    List<String> patterns = new ArrayList<>(DISORDER_TERMS);
    patterns.addAll(ASSERTION_PATTERNS);
    return List.copyOf(patterns);
  }

  /**
   * 과잉 추론 패턴 문자열 전체를 돌려준다.
   *
   * @return 패턴 문자열 목록
   */
  static List<String> allOverinferencePatterns() {
    return OVERINFERENCE_PATTERNS;
  }

  private static List<String> match(List<Pattern> patterns, String text) {
    if (text == null || text.isBlank()) {
      return List.of();
    }
    List<String> matched = new ArrayList<>();
    for (Pattern pattern : patterns) {
      if (pattern.matcher(text).find()) {
        matched.add(pattern.pattern());
      }
    }
    return List.copyOf(matched);
  }

  private static List<Pattern> compile(List<String> patterns) {
    return patterns.stream().map(pattern -> Pattern.compile(pattern, FLAGS)).toList();
  }
}
