ALTER TABLE conversation_messages
    ADD COLUMN tts_voice VARCHAR(50) NULL COMMENT 'AI 질문 TTS 생성 음성 코드' AFTER speech_status,
    ADD COLUMN tts_speed DECIMAL(3,2) NULL COMMENT 'AI 질문 TTS 생성 재생 속도' AFTER tts_voice;
