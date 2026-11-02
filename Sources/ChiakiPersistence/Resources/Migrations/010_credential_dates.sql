ALTER TABLE profile_npsso ADD COLUMN core_obtained_at_ms INTEGER
    CHECK (core_obtained_at_ms IS NULL OR typeof(core_obtained_at_ms) = 'integer');
ALTER TABLE profile_npsso ADD COLUMN core_expires_at_ms INTEGER
    CHECK (core_expires_at_ms IS NULL OR typeof(core_expires_at_ms) = 'integer');
ALTER TABLE profile_tokens ADD COLUMN access_obtained_at_ms INTEGER
    CHECK (access_obtained_at_ms IS NULL OR typeof(access_obtained_at_ms) = 'integer');
ALTER TABLE profile_tokens ADD COLUMN refresh_obtained_at_ms INTEGER
    CHECK (refresh_obtained_at_ms IS NULL OR typeof(refresh_obtained_at_ms) = 'integer');
ALTER TABLE profile_tokens ADD COLUMN refresh_expires_at_ms INTEGER
    CHECK (refresh_expires_at_ms IS NULL OR typeof(refresh_expires_at_ms) = 'integer');
