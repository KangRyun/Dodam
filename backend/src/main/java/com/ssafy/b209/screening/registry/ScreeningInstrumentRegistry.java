package com.ssafy.b209.screening.registry;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * 표준화 선별도구 런타임 allow-list다.
 *
 * <p><strong>여기 없는 도구는 존재하지 않는다.</strong> 등록부에 없는 식별자로 결과를 기록하려는 요청은 거절된다 — 그렇게 하지 않으면 임의의 검사명이 아동
 * 기록에 남는다.
 *
 * <p>현재 <strong>아홉 개 전부 {@link ScreeningInstrumentState#DISABLED}</strong> 다. 이 파일을 고쳐 {@code
 * ENABLED} 로 바꾸는 것만으로는 도구가 켜지지 않아야 한다 — 켜기 전에 도구별 활성화 체크리스트(정체성·근거·라이선스·제품·안전·개인정보·승인)를 통과하고 임상
 * 책임자와 법무의 승인 ID가 남아야 한다.
 *
 * <p>적용 연령은 공식 매뉴얼·타당화 문헌이 밝힌 범위만 개월로 옮겼다. 정확한 한국어판 도구를 임상위원회가 아직 고르지 않은 항목은 {@code null} 로 둔다 —
 * 짐작해 넣으면 지어낸 적용 연령이 된다.
 *
 * <p>등록부를 고치면 {@link #REGISTRY_VERSION} 과 {@link #AS_OF} 를 함께 올린다.
 */
public final class ScreeningInstrumentRegistry {

  /** 등록부 버전이다. 문장이나 범위를 고치면 함께 올린다. */
  public static final String REGISTRY_VERSION = "1.0.0";

  /** 등록부 기준일이다. 연 1회 이상 또는 주요 가이드 변경 시 재검토한다. */
  public static final String AS_OF = "2026-08-07";

  /** 국가 영유아건강검진의 공식 발달선별. 공식 결과 연결만 검토 대상이며 제품이 문항을 복제하거나 채점하지 않는다. */
  public static final String K_DST = "K_DST";

  /** 라이선스 기반 선택적 발달선별 후보. */
  public static final String K_CDI_DEVELOPMENT = "K_CDI_DEVELOPMENT";

  /** 광범위 정서·행동 선별 후보. 국내 타당화 표본이 만 7~12세라 4~6세 핵심 도구로 쓰지 않는다. */
  public static final String PSC_K = "PSC_K";

  /** 광범위 정서·행동 선별 후보이며 강점 영역을 함께 본다. */
  public static final String SDQ_KR = "SDQ_KR";

  /** 주의·과잉행동 표적 평가. 그림일기만으로 자동 권고하지 않는다. */
  public static final String K_ARS_5 = "K_ARS_5";

  /** 실행기능 평가. 지우기·멈춤·주제 전환 수로 대체하지 않는다. */
  public static final String K_BRIEF_2 = "K_BRIEF_2";

  /** 불안 선별. 정확한 한국어판 도구가 선정되기 전이라 적용 연령을 확정하지 않았다. */
  public static final String ANXIETY_SCREEN_KR = "ANXIETY_SCREEN_KR";

  /** 우울 선별. 만 11세 이하 일반 선별은 근거가 충분하지 않다. */
  public static final String DEPRESSION_SCREEN_KR = "DEPRESSION_SCREEN_KR";

  /** 자살 선별. 일반 앱 기능이 아니라 임상 안전 운영 체계가 있을 때만 쓰는 위기 경로다. */
  public static final String ASQ = "ASQ";

  private static final Map<String, ScreeningInstrument> INSTRUMENTS = buildRegistry();

  private ScreeningInstrumentRegistry() {}

  private static Map<String, ScreeningInstrument> buildRegistry() {
    Map<String, ScreeningInstrument> registry = new LinkedHashMap<>();
    put(
        registry,
        new ScreeningInstrument(
            K_DST,
            "한국 영유아 발달선별검사 K-DST",
            ScreeningInstrumentState.DISABLED,
            9,
            71,
            Set.of("GUARDIAN"),
            "OFFICIAL_SERVICE_ONLY",
            "공식 발달선별 결과이며 진단은 아닙니다. 결과에 따라 정밀평가가 필요할 수 있습니다.",
            List.of("K_DST_MANUAL", "K_DST_VALIDATION"),
            Set.of(ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("공식 결과 연동 방식과 이용조건 확정", "결과 라벨 매핑 임상 승인")));
    put(
        registry,
        new ScreeningInstrument(
            K_CDI_DEVELOPMENT,
            "K-CDI 아동발달검사",
            ScreeningInstrumentState.DISABLED,
            15,
            77,
            Set.of("GUARDIAN", "TEACHER"),
            "LICENSED_VENDOR_ONLY",
            "발달선별 결과이며 진단이 아닙니다. 공식 지침과 전문가 해석을 따릅니다.",
            List.of("K_CDI_DEV_VENDOR"),
            Set.of(
                ScreeningActivationBlocker.LICENSE, ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("상업·디지털·전자화·결과재표시 권한", "임상위원회 승인")));
    put(
        registry,
        new ScreeningInstrument(
            PSC_K,
            "한국판 Pediatric Symptom Checklist",
            ScreeningInstrumentState.DISABLED,
            84,
            155,
            Set.of("GUARDIAN"),
            "APPROVED_DETERMINISTIC_ENGINE_OR_PROVIDER",
            "선별 결과는 진단이 아니며 추가 확인이 필요한지를 돕는 자료입니다.",
            List.of("PSC_K_VALIDATION", "PSC_OWNER"),
            Set.of(
                ScreeningActivationBlocker.LICENSE, ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("한국어 양식의 디지털·상업 이용 권한", "한국 규준·절단점·결과 문구 임상 승인", "위양성·위음성 설명과 후속 경로")));
    put(
        registry,
        new ScreeningInstrument(
            SDQ_KR,
            "한국어판 Strengths and Difficulties Questionnaire",
            ScreeningInstrumentState.DISABLED,
            48,
            215,
            Set.of("GUARDIAN", "TEACHER", "CHILD_11_PLUS"),
            "LICENSED_PROVIDER_ONLY",
            "선별 결과이며 진단이 아닙니다. 응답자와 공식 채점 기준을 함께 확인해야 합니다.",
            List.of("SDQ_OWNER", "SDQ_KOREAN_FORMS", "SDQ_SCORING_LICENSE"),
            Set.of(
                ScreeningActivationBlocker.LICENSE, ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("컴퓨터 채점 및 상업 전자화 라이선스", "한국 적용 기준 임상 승인")));
    put(
        registry,
        new ScreeningInstrument(
            K_ARS_5,
            "K-ARS-5 한국판 ADHD 평가척도 5판",
            ScreeningInstrumentState.DISABLED,
            60,
            191,
            Set.of("GUARDIAN", "TEACHER"),
            "LICENSED_VENDOR_OR_CLINICIAN",
            "평가척도 결과만으로 ADHD를 진단하지 않으며, 가정과 학교 등 여러 환경의 기능 영향을 전문가가 함께 확인합니다.",
            List.of("K_ARS_5_VENDOR", "AAP_ADHD_2019"),
            Set.of(
                ScreeningActivationBlocker.LICENSE, ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("공식 도구·매뉴얼·라이선스 확인", "다중 정보원과 전문가 검토 경로")));
    put(
        registry,
        new ScreeningInstrument(
            K_BRIEF_2,
            "K-BRIEF-2 한국판 실행기능 행동평가 검사 2판",
            ScreeningInstrumentState.DISABLED,
            60,
            227,
            Set.of("GUARDIAN", "CHILD_11_PLUS"),
            "LICENSED_VENDOR_OR_CLINICIAN",
            "그림일기 지우기·멈춤·대화 전환을 실행기능 점수로 바꾸지 않습니다.",
            List.of("K_BRIEF_2_VENDOR"),
            Set.of(ScreeningActivationBlocker.LICENSE),
            List.of("공식 매뉴얼·라이선스·응답자별 연령 확인", "전문가 결과 import만 우선 구현")));
    put(
        registry,
        new ScreeningInstrument(
            ANXIETY_SCREEN_KR,
            "한국어 불안 선별도구",
            ScreeningInstrumentState.DISABLED,
            null,
            null,
            Set.of("AGE_APPROPRIATE"),
            "NONE",
            "정확한 한국어 도구와 후속 평가 체계가 승인되기 전에는 사용할 수 없습니다.",
            List.of("USPSTF_ANXIETY"),
            Set.of(ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("정확한 도구·한국어판·연령·규준·라이선스 선정", "양성 후 임상 평가 체계")));
    put(
        registry,
        new ScreeningInstrument(
            DEPRESSION_SCREEN_KR,
            "한국어 아동·청소년 우울 선별도구",
            ScreeningInstrumentState.DISABLED,
            null,
            null,
            Set.of("CHILD", "GUARDIAN_OR_CLINICIAN_AS_TOOL_REQUIRES"),
            "NONE",
            "선별은 진단이 아니며, 11세 이하의 일반 선별 근거는 충분하지 않습니다.",
            List.of("USPSTF_DEPRESSION"),
            Set.of(ScreeningActivationBlocker.CLINICAL_APPROVAL),
            List.of("정확한 한국어 도구·라이선스·연령 승인", "치료·의뢰·안전 대응 체계")));
    put(
        registry,
        new ScreeningInstrument(
            ASQ,
            "Ask Suicide-Screening Questions",
            ScreeningInstrumentState.DISABLED,
            96,
            227,
            Set.of("CHILD_IN_CLINICAL_SETTING"),
            "TRAINED_CLINICIAN_WORKFLOW",
            "일반 그림일기 리포트 기능이 아니며, 양성 뒤 훈련된 임상가의 안전평가가 필요합니다.",
            List.of("NIMH_ASQ"),
            Set.of(ScreeningActivationBlocker.CLINICAL_OPERATIONS),
            List.of("의료·임상 운영 주체", "양성 즉시 BSSA와 disposition 경로", "보호자 부재 면담 등 현장 절차")));
    return Map.copyOf(registry);
  }

  private static void put(Map<String, ScreeningInstrument> registry, ScreeningInstrument entry) {
    registry.put(entry.instrumentId(), entry);
  }

  /**
   * 등록부에 실린 도구를 찾는다.
   *
   * @param instrumentId 도구 식별자
   * @return 등록된 도구이며 없으면 빈 {@link Optional}
   */
  public static Optional<ScreeningInstrument> find(String instrumentId) {
    return instrumentId == null
        ? Optional.empty()
        : Optional.ofNullable(INSTRUMENTS.get(instrumentId));
  }

  /**
   * 등록된 도구 전체를 돌려준다.
   *
   * @return 등록 순서를 유지한 도구 목록
   */
  public static List<ScreeningInstrument> all() {
    return List.copyOf(INSTRUMENTS.values());
  }
}
