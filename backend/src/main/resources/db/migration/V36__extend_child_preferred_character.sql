-- 캐릭터 선택 캐러셀에 신규 도담이 3종(EXPLORER, RIBBON, PRINCE)을 추가한다(S15P11B209-866).
-- 기존 4종은 그대로 유지하며 저장된 값을 변환하지 않는다. NULL 허용 계약도 V28과 같다.

ALTER TABLE children
    DROP CHECK ck_children_preferred_character,
    ADD CONSTRAINT ck_children_preferred_character
        CHECK (
            preferred_character IS NULL
            OR preferred_character IN (
                'BASE',
                'PRINCESS',
                'DINO',
                'OCTOPUS',
                'EXPLORER',
                'RIBBON',
                'PRINCE'
            )
        );
