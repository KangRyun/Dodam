ALTER TABLE conversation_messages
    ADD COLUMN tts_tone_profile VARCHAR(50) NULL
    COMMENT '질문 TTS 캐시를 구분하는 서버 고정 캐릭터·상황 말투 프로필',
    ADD CONSTRAINT ck_conversation_messages_tts_tone_profile
        CHECK (
            tts_tone_profile IS NULL
            OR tts_tone_profile IN (
                'CHARACTER_DEFAULT_V1',
                'CHARACTER_CELEBRATING_V1',
                'CHARACTER_ENCOURAGING_V1'
            )
        );
