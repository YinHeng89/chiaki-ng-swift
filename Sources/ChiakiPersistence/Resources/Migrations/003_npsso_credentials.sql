CREATE TABLE profile_npsso (
    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    encrypted_value BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    acquired_at REAL NOT NULL,
    validated_at REAL NOT NULL,
    expires_at REAL,
    expiry_source TEXT NOT NULL CHECK(expiry_source IN ('unknown','cookie')),
    CHECK((expiry_source='unknown' AND expires_at IS NULL) OR (expiry_source='cookie' AND expires_at IS NOT NULL))
);
