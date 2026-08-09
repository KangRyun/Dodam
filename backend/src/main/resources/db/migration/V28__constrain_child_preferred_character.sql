UPDATE children
   SET preferred_character = 'BASE'
 WHERE preferred_character IS NOT NULL
   AND preferred_character NOT IN ('BASE', 'PRINCESS', 'DINO', 'OCTOPUS');

ALTER TABLE children
    ADD CONSTRAINT ck_children_preferred_character
        CHECK (
            preferred_character IS NULL
            OR preferred_character IN ('BASE', 'PRINCESS', 'DINO', 'OCTOPUS')
        );
