ALTER TABLE consoles ADD COLUMN firmware TEXT
    CHECK (firmware IS NULL OR (firmware IN ('ps4_8', 'ps4_9', 'ps4_10', 'ps5')
        AND (firmware = 'ps5') = (generation = 'ps5')));
ALTER TABLE consoles ADD COLUMN name_source TEXT NOT NULL DEFAULT 'renamed'
    CHECK (name_source IN ('generation', 'account', 'pairing', 'discovered', 'renamed'));
UPDATE consoles SET firmware = CASE generation WHEN 'ps5' THEN 'ps5' ELSE 'ps4_10' END;
