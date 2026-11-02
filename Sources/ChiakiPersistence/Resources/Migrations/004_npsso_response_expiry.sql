CREATE TABLE profile_npsso_v4 (
    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    encrypted_value BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    acquired_at REAL NOT NULL,
    validated_at REAL NOT NULL,
    expires_at REAL,
    expiry_source TEXT NOT NULL CHECK(expiry_source IN ('unknown','cookie','sony_response')),
    CHECK((expiry_source='unknown' AND expires_at IS NULL) OR (expiry_source IN ('cookie','sony_response') AND expires_at IS NOT NULL))
);
INSERT INTO profile_npsso_v4 SELECT * FROM profile_npsso;
DROP TABLE profile_npsso;
ALTER TABLE profile_npsso_v4 RENAME TO profile_npsso;
