CREATE TABLE profile_npsso_019 (
    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    encrypted_value BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    acquired_at INTEGER NOT NULL CHECK (typeof(acquired_at) = 'integer'),
    validated_at INTEGER NOT NULL CHECK (typeof(validated_at) = 'integer'),
    expires_at INTEGER CHECK (expires_at IS NULL OR typeof(expires_at) = 'integer'),
    expiry_source TEXT NOT NULL CHECK(expiry_source IN ('unknown', 'cookie', 'token_response')),
    CHECK((expiry_source = 'unknown' AND expires_at IS NULL)
        OR (expiry_source IN ('cookie', 'token_response') AND expires_at IS NOT NULL))
);
INSERT INTO profile_npsso_019(profile_id, encrypted_value, key_version, acquired_at, validated_at, expires_at,
    expiry_source)
SELECT profile_id, encrypted_value, key_version, acquired_at, validated_at, expires_at,
       CASE expiry_source WHEN 'sony_response' THEN 'token_response' ELSE expiry_source END
FROM profile_npsso;
DROP TABLE profile_npsso;
ALTER TABLE profile_npsso_019 RENAME TO profile_npsso;
