UPDATE profile_npsso SET acquired_at = core_obtained_at_ms / 1000.0
    WHERE core_obtained_at_ms IS NOT NULL AND expiry_source = 'unknown'
    AND abs(acquired_at * 1000.0 - core_obtained_at_ms) >= 1;
UPDATE profile_npsso SET expires_at = core_expires_at_ms / 1000.0, expiry_source = 'sony_response'
    WHERE core_expires_at_ms IS NOT NULL AND expiry_source = 'unknown';
ALTER TABLE profile_npsso DROP COLUMN core_obtained_at_ms;
ALTER TABLE profile_npsso DROP COLUMN core_expires_at_ms;
