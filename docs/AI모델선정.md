# 도담 AI 모델 선정 (1차 MVP 베이스라인)

> **방침:** 외부 API 우선(빠른 베이스라인). 전부 **GMS**(SSAFY OpenAI 호환 게이트웨이) **단일 키**로 접근.
> **확정일:** 2026-07-22 · **파이프라인 버전:** 0.1.0
> ⚠️ 아동 실데이터(음성·대화)를 외부로 보내는 것은 **프로덕션 시 동의·약관 재검토**(가드레일). 베이스라인은 **테스트 입력만**.

## 확정 요약

| 단계 | 모델 | 접근 | 한 줄 이유 |
|------|------|------|-----------|
| 대화 LLM | `gpt-4o-mini` | GMS | 저지연·저비용, 한국어 양호 |
| STT (음성→텍스트) | `whisper-1` | GMS | 다국어 음성인식, 동일 키 |
| TTS (텍스트→음성) | `gpt-4o-mini-tts` (voice=`fable`) | GMS | ★ **지시형** — 곰돌이 톤 지정 가능 |

접근: `base_url = https://gms.ssafy.io/gmsapi/api.openai.com/v1`, 키 = `GMS_KEY`(.env, **로그·커밋 금지**).

---

## 1. 대화 LLM — `gpt-4o-mini`
- **특징:** OpenAI 소형 GPT. 저지연·저비용. 한국어 대화 양호. `temperature`로 창의성 제어(아동 대화는 0.6 이하 권장).
- **선정 이유:** 베이스라인 속도·비용, GMS 기본 예시 모델. 대화 품질 부족 시 상위 모델로 상향 여지.

## 2. STT — `whisper-1`
- **특징:** OpenAI Whisper 기반 다국어 음성→텍스트. 한국어 지원.
- **선정 이유:** GMS 동일 키로 접근. **아동 발음** 정확도는 실측 필요(어린이 음성은 성인보다 인식률이 낮을 수 있음 → 추후 검증 항목).

## 3. TTS — `gpt-4o-mini-tts` (voice=`fable`) ★

### 후보 비교
| 모델/서비스 | 한국어 | 캐릭터·아동 적합 | 톤 지시(steer) | 접근 | 메모 |
|------------|--------|-----------------|----------------|------|------|
| **`gpt-4o-mini-tts`** | 다국어(한국어 O) | fable=만화적·개성 / nova=밝음 / coral=친근 | ✅ *"밝고 장난기 있는 곰돌이처럼"* 지시 가능 | **GMS** | ★ **채택** (2025.3 출시) |
| `tts-1` / `tts-1-hd` | 다국어 | 동일 보이스군 | ❌ 지시 불가 | GMS | hd=고음질, 톤 지시 없음 |
| CLOVA Voice (네이버) | **한국어 네이티브 최상** | 감정·스타일 다양 | 스타일 선택 | 별도 키 | 한국어 품질 **대안 1순위** |
| ElevenLabs | 한국어 O | 캐릭터·보이스클로닝 강함 | 지시·감정 | 별도 키 | 자연스러움 최상급, 비용↑ |
| Google / Azure TTS | 한국어 뉴럴 | 스타일(명랑 등) | 스타일 태그 | 별도 키 | 안정적, 별도 계정 |

### 채택 근거 — `gpt-4o-mini-tts`, voice=`fable`
- **지시형(steerable)** 이 핵심: "어떻게 말할지"를 `instructions`로 지정 → *"따뜻하고 장난기 있는 곰돌이 캐릭터처럼, 아이에게 밝고 부드럽게, 쉬운 말로"* → 요구사항("자연스럽고 만화 캐릭터 같은 아이 친화 목소리")에 가장 부합.
- **GMS 단일 키**로 STT·LLM과 통일 → 계정·키 관리 단순, 베이스라인 최속.
- 속도 조절 0.25~4.0 지원.
- **보이스 후보 순위:** `fable`(만화적·개성) > `nova`(밝음·상냥) > `coral`(친근). 실제 들어보고 교체.

### 리스크·대안
- ⚠️ **한국어 자연스러움**이 CLOVA Voice보다 떨어질 수 있음 → 실측(들어보기) 후 부족하면 **CLOVA Voice로 교체**(별도 키·계정 필요).
- ⚠️ `gpt-4o-mini-tts`가 **GMS 프록시로 열려 있는지 실호출 확인** 필요(안 되면 `tts-1`로 폴백하되 톤 지시 포기).

---

## 가드레일 메모
- 아동 **음성(STT 입력)·대화 텍스트**를 외부(OpenAI/GMS)로 전송 → **프로덕션 전 동의·약관 검토**. 베이스라인은 테스트 입력만.
- `GMS_KEY`·원본 발화는 **로그 금지**. 요청에 아이 실명 대신 **별칭**.
- 분석 결과에 `{model_id, prompt_version, pipeline_version}` 기록(재현·재분석).

## 출처
- [OpenAI — Introducing next-generation audio models](https://openai.com/index/introducing-our-next-generation-audio-models/)
- [OpenAI API — gpt-4o-mini-tts 모델](https://developers.openai.com/api/docs/models/gpt-4o-mini-tts)
- [OpenAI API — Text to speech 가이드](https://platform.openai.com/docs/guides/text-to-speech)
- [네이버 CLOVA Voice](https://www.ncloud.com/product/aiService/clovaVoice)
- [한국 TTS 서비스 총정리 2026 (타입캐스트)](https://typecast.ai/kr/learn/tts-recommendation-korea/)
