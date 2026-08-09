INSERT IGNORE INTO drawing_types (
    code,
    name,
    activity_category,
    selectable_by,
    recommended_age_min,
    recommended_age_max,
    guide_text,
    is_active,
    display_order
) VALUES
    (
        'ART_DIARY',
        '그림 일기',
        'GENERAL',
        'BOTH',
        4,
        12,
        '오늘 있었던 일이나 기억에 남는 순간을 그림으로 표현해 보세요.',
        TRUE,
        10
    ),
    (
        'FREE_DRAWING',
        '자유 그리기',
        'GENERAL',
        'BOTH',
        4,
        12,
        '그리고 싶은 것을 자유롭게 그려 보세요.',
        TRUE,
        20
    ),
    (
        'EMOTION_COLORING',
        '마음 색칠하기',
        'GENERAL',
        'BOTH',
        4,
        12,
        '지금 마음과 어울리는 색을 골라 자유롭게 표현해 보세요.',
        TRUE,
        30
    ),
    (
        'WEATHER_MIND',
        '마음 날씨 그리기',
        'GENERAL',
        'BOTH',
        4,
        12,
        '지금 마음을 날씨로 떠올려 그림으로 표현해 보세요.',
        TRUE,
        40
    );
