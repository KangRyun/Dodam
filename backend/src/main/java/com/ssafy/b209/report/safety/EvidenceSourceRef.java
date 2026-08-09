package com.ssafy.b209.report.safety;

/**
 * 근거의 말단 원본을 가리키는 참조다(875 계약 §4 {@code sourceRef}).
 *
 * <p>독립 근거 수는 이 값의 합집합 크기로 센다. 그래서 {@code equals}/{@code hashCode}가 계수의 기준이 되며, 레코드 기본 구현이 {@code
 * kind}+{@code id} 동등성을 그대로 제공한다. 서로 다른 테이블의 같은 행 번호를 같은 원본으로 세지 않도록 {@code kind}를 반드시 키에 포함한다.
 *
 * <p><strong>검증하지 않는 생성자다.</strong> 잘못된 입력이 게이트까지 도달해 사유 코드로 걸러지는 것이 목적이므로 여기서 예외를 던지지 않는다. 형태 검증은
 * {@link InterpretationPublicationGate}가 한다.
 *
 * @param kind 원본 레코드 종류이며 해석할 수 없으면 {@code null}
 * @param id BE가 발급한 원본 행 식별자 문자열이며 없으면 {@code null}
 */
public record EvidenceSourceRef(EvidenceSourceKind kind, String id) {}
