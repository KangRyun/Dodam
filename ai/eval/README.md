# 프롬프트 회귀 평가 (S15P11B209-792)

786이 프롬프트를 활동유형별로 갈랐지만, 검증은 *"규칙이 파일에 존재하는가"* 까지였다.
모델이 그 규칙을 **실제로 지키는지** 판정할 수단이 없으면 이후 프롬프트·모델 변경이
개선인지 회귀인지 알 수 없다. 이 하네스가 그 판정을 맡는다.

## 두 층

| 층 | 무엇을 보는가 | GMS | 결정적 | 비용 |
|---|---|---|---|---|
| **A. 조립** | 활동유형에 맞는 변형이 골렸는가 · 말투/가드레일/공통 블록이 실렸는가 · 치환이 남지 않았는가 | 불필요 | 예 | 0 |
| **B. 준수** | 모델이 그 규칙을 지키는가 — 작별 인사 · 주제 이탈 · 정정 수용 · 개인정보 · 리포트 JSON | 필요 | 아니오 | 회당 8콜 |

A층은 CI에 넣어도 된다. B층은 프롬프트·모델을 바꿨을 때 손으로 돌린다.

## 실행

```bash
cd ai
python -m eval.run --layer a          # 조립만. 키 없이 돌고 비용 0
python -m eval.run                    # A + B (GMS 실호출)
python -m eval.run --repeat 3         # B층 표본 3회 — LLM은 비결정적이라 1회는 근거가 얇다
python -m eval.run --out /tmp/x.md    # 결과 경로 지정
```

기본 산출 경로는 `docs/ai/prompt-eval-<날짜시각>.md`. 종료 코드 = 실패 건수(게이트로 쓸 수 있다).

### 의존성

`question_service`·`report_client`는 **torch·ultralytics 없이** import 된다(YOLO를 안 거친다).
그래서 평가셋은 가벼운 환경에서 돈다:

```bash
python -m venv .venv && .venv/bin/pip install pydantic openai prometheus_client numpy python-dotenv
```

B층은 프로젝트 루트 `.env`의 `GMS_KEY`를 쓴다. 키가 없으면 B층을 건너뛰고 A층 결과만 남긴다.

## 케이스

| ID | 무엇을 지키는가 | 근거 |
|---|---|---|
| `Q1_first_htp` | 서술 세부 소비 · 주제(집) 이탈 없음 | 786 / 713 |
| `Q2_first_diary` | 자유 그림을 HTP 틀로 다루지 않음 | 786 치명 1 |
| `Q3_first_no_detection` | 탐지 0건에서 포기 문구로 굳지 않음 | 786 품질 |
| `Q4_next_normal` | **작별 인사 금지** — 턴 제어는 BE 소유 | 786 치명 2 |
| `Q5_next_correction` | 아이가 정정한 이름을 따름 | 763 / conversation_common |
| `Q6_injection` | 인젝션이 LLM에 닿기 전 차단 (**GMS 미호출**) | 742 |
| `Q9_privacy` | 주소·학교·전화번호를 되묻지 않음 | 786 안전 / 9절 |
| `R7_report_htp` | 주제별 블록 종합 · 내부 코드 미노출 · RAG 시도 | 786 치명 3 / 740 / 614 |
| `R8_report_diary` | `RAG_NOT_APPLICABLE` · HTP 틀 미전제 | 786 결정 |

## 설계상 알아둘 것

- **계약 경로만 잰다.** `question_service.generate()`(BE가 실제로 부르는 경로)를 쓴다.
  draft 경로(`llm_client.first_question`)는 사후 필터가 다르다 —
  계약 경로는 `question_safety.evaluate`, draft 경로는 `answer_check.enforce`.
  운영에서 도는 쪽을 재지 않으면 의미가 없다.

- **금지어 정규식은 `answer_check`에서 import한다.** 여기서 새로 정의하지 않는다 —
  두 벌이 되면 한쪽만 고쳐지는 순간 어긋난다(786이 길이 규칙 3중복으로 겪은 일).

- **변형 판정은 '배타적 지문'으로 한다.** 두 변형은 공통 문장을 꽤 공유해서, 공유 줄로
  판정하면 반대 변형이 실려도 통과한다(negative control에서 실제로 새어 나갔다).
  `checks._signature_lines`가 파일에서 지문을 자동 추출하므로 문구를 코드에 베껴 적지 않는다 —
  프롬프트가 바뀌어도 판정이 따라 움직인다.

- **입력은 전부 합성이다.** 아동 실그림·실발화는 평가셋에 넣지 않는다(가드레일 9절, 707과 같은 결론).
  그래서 `cases.py`는 저장소에 커밋해도 된다.

- ⚠️ `report_client._build_rag_query`가 **VLM 관찰 서술 원문을 임베딩 질의로 쓴다.**
  서술 프롬프트를 바꾸면 검색 청크와 `RAG_SCORE_THRESHOLD`(0.35) 통과 여부가 함께 바뀐다 —
  R7의 RAG 항목 변화를 리포트 프롬프트 탓으로만 읽으면 오진한다.

## A/B 비교가 기본이 아닌 이유

티켓 초안은 "구 프롬프트 / 신 프롬프트 전후 비교"였다. 그런데 786이 이미 머지·배포돼
(`7be2e3ac`, 2026-08-03) 구 프롬프트는 운영에 없다. 그 비교로 얻는 건 *이미 나간 변경이
좋았나* 뿐이라, 기본 동작은 **현재 프롬프트에 대한 판정 기반 회귀 스위트**로 두었다.
786의 사후 검증은 이 스위트를 한 번 돌리는 것으로 갈음한다.
