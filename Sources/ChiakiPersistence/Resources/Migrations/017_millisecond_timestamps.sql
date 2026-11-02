CREATE TABLE profiles_017 (
    id TEXT NOT NULL PRIMARY KEY,
    display_name TEXT NOT NULL CHECK(length(trim(display_name)) > 0),
    auth_method TEXT NOT NULL CHECK(auth_method IN ('npsso', 'account_id')),
    psn_account_id BLOB NOT NULL CHECK(typeof(psn_account_id) = 'blob' AND length(psn_account_id) = 8),
    psn_online_id TEXT,
    created_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
        CHECK (typeof(created_at) = 'integer'),
    updated_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
        CHECK (typeof(updated_at) = 'integer')
);
INSERT INTO profiles_017(id, display_name, auth_method, psn_account_id, psn_online_id, created_at, updated_at)
SELECT id, display_name, auth_method, psn_account_id, psn_online_id,
       COALESCE(CAST(round((julianday(created_at) - 2440587.5) * 86400000) AS INTEGER),
                CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER)),
       COALESCE(CAST(round((julianday(updated_at) - 2440587.5) * 86400000) AS INTEGER),
                CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
FROM profiles;
DROP TABLE profiles;
ALTER TABLE profiles_017 RENAME TO profiles;

CREATE TABLE registrations_017 (
    id TEXT NOT NULL PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    console_id TEXT NOT NULL REFERENCES consoles(id) ON DELETE CASCADE,
    encrypted_credentials BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    created_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
        CHECK (typeof(created_at) = 'integer'),
    remote_device_id BLOB
        CHECK(remote_device_id IS NULL OR (typeof(remote_device_id) = 'blob' AND length(remote_device_id) = 32)),
    UNIQUE (profile_id, console_id)
);
INSERT INTO registrations_017(id, profile_id, console_id, encrypted_credentials, key_version, created_at, remote_device_id)
SELECT id, profile_id, console_id, encrypted_credentials, key_version,
       COALESCE(CAST(round((julianday(created_at) - 2440587.5) * 86400000) AS INTEGER),
                CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER)),
       remote_device_id
FROM registrations;
DROP TABLE registrations;
ALTER TABLE registrations_017 RENAME TO registrations;
CREATE INDEX registrations_by_console ON registrations(console_id);

CREATE TABLE profile_tokens_017 (
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    credential_kind TEXT NOT NULL CHECK(credential_kind IN ('remote_play', 'mobile_sso')),
    encrypted_tokens BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    expires_at INTEGER NOT NULL CHECK (typeof(expires_at) = 'integer'),
    updated_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
        CHECK (typeof(updated_at) = 'integer'),
    access_obtained_at_ms INTEGER
        CHECK (access_obtained_at_ms IS NULL OR typeof(access_obtained_at_ms) = 'integer'),
    refresh_obtained_at_ms INTEGER
        CHECK (refresh_obtained_at_ms IS NULL OR typeof(refresh_obtained_at_ms) = 'integer'),
    refresh_expires_at_ms INTEGER
        CHECK (refresh_expires_at_ms IS NULL OR typeof(refresh_expires_at_ms) = 'integer'),
    PRIMARY KEY(profile_id, credential_kind)
);
INSERT INTO profile_tokens_017(profile_id, credential_kind, encrypted_tokens, key_version, expires_at, updated_at,
    access_obtained_at_ms, refresh_obtained_at_ms, refresh_expires_at_ms)
SELECT profile_id, credential_kind, encrypted_tokens, key_version,
       COALESCE(CAST(round((julianday(expires_at) - 2440587.5) * 86400000) AS INTEGER), 0),
       COALESCE(CAST(round((julianday(updated_at) - 2440587.5) * 86400000) AS INTEGER),
                CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER)),
       CAST(access_obtained_at_ms AS INTEGER), CAST(refresh_obtained_at_ms AS INTEGER),
       CAST(refresh_expires_at_ms AS INTEGER)
FROM profile_tokens;
DROP TABLE profile_tokens;
ALTER TABLE profile_tokens_017 RENAME TO profile_tokens;

CREATE TABLE profile_npsso_017 (
    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    encrypted_value BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    acquired_at INTEGER NOT NULL CHECK (typeof(acquired_at) = 'integer'),
    validated_at INTEGER NOT NULL CHECK (typeof(validated_at) = 'integer'),
    expires_at INTEGER CHECK (expires_at IS NULL OR typeof(expires_at) = 'integer'),
    expiry_source TEXT NOT NULL CHECK(expiry_source IN ('unknown', 'cookie', 'sony_response')),
    CHECK((expiry_source = 'unknown' AND expires_at IS NULL)
        OR (expiry_source IN ('cookie', 'sony_response') AND expires_at IS NOT NULL))
);
INSERT INTO profile_npsso_017(profile_id, encrypted_value, key_version, acquired_at, validated_at, expires_at,
    expiry_source)
SELECT profile_id, encrypted_value, key_version,
       CAST(round(CAST(acquired_at AS REAL) * 1000) AS INTEGER),
       CAST(round(CAST(validated_at AS REAL) * 1000) AS INTEGER),
       CAST(round(CAST(expires_at AS REAL) * 1000) AS INTEGER),
       expiry_source
FROM profile_npsso;
DROP TABLE profile_npsso;
ALTER TABLE profile_npsso_017 RENAME TO profile_npsso;

CREATE TABLE account_resource_cache_017 (
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    resource TEXT NOT NULL CHECK(resource IN ('profile', 'avatar', 'pscloud')),
    payload BLOB NOT NULL,
    source_url TEXT,
    fetched_at INTEGER NOT NULL CHECK (typeof(fetched_at) = 'integer'),
    expires_at INTEGER NOT NULL CHECK (typeof(expires_at) = 'integer'),
    PRIMARY KEY(profile_id, resource)
);
INSERT INTO account_resource_cache_017(profile_id, resource, payload, source_url, fetched_at, expires_at)
SELECT profile_id, resource, payload, source_url,
       CAST(round(CAST(fetched_at AS REAL) * 1000) AS INTEGER),
       CAST(round(CAST(expires_at AS REAL) * 1000) AS INTEGER)
FROM account_resource_cache;
DROP TABLE account_resource_cache;
ALTER TABLE account_resource_cache_017 RENAME TO account_resource_cache;

CREATE TABLE kakusan_identity_017 (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    encrypted_seed BLOB NOT NULL,
    public_key BLOB NOT NULL CHECK (length(public_key) = 32),
    key_version INTEGER NOT NULL CHECK (key_version > 0),
    created_at INTEGER NOT NULL CHECK (typeof(created_at) = 'integer')
);
INSERT INTO kakusan_identity_017(id, encrypted_seed, public_key, key_version, created_at)
SELECT id, encrypted_seed, public_key, key_version, CAST(round(CAST(created_at AS REAL) * 1000) AS INTEGER)
FROM kakusan_identity;
DROP TABLE kakusan_identity;
ALTER TABLE kakusan_identity_017 RENAME TO kakusan_identity;

CREATE TABLE kakusan_peers_017 (
    public_key BLOB PRIMARY KEY NOT NULL CHECK (length(public_key) = 32),
    fingerprint BLOB NOT NULL CHECK (length(fingerprint) = 32),
    nickname TEXT NOT NULL CHECK (length(trim(nickname)) > 0),
    first_verified_at INTEGER NOT NULL CHECK (typeof(first_verified_at) = 'integer'),
    last_seen_at INTEGER NOT NULL CHECK (typeof(last_seen_at) = 'integer')
);
INSERT INTO kakusan_peers_017(public_key, fingerprint, nickname, first_verified_at, last_seen_at)
SELECT public_key, fingerprint, nickname,
       CAST(round(CAST(first_verified_at AS REAL) * 1000) AS INTEGER),
       CAST(round(CAST(last_seen_at AS REAL) * 1000) AS INTEGER)
FROM kakusan_peers ORDER BY rowid;
DROP TABLE kakusan_peers;
ALTER TABLE kakusan_peers_017 RENAME TO kakusan_peers;
CREATE UNIQUE INDEX kakusan_peers_nickname ON kakusan_peers(nickname COLLATE NOCASE);

UPDATE settings
SET value_json = json_set(
    value_json, '$.lastConnection.connectedAt',
    CAST(round((json_extract(value_json, '$.lastConnection.connectedAt') + 978307200) * 1000) AS INTEGER)
)
WHERE key = 'cloud.datacenters.v1' AND json_valid(value_json)
  AND json_type(value_json, '$.lastConnection.connectedAt') IN ('integer', 'real');

CREATE TABLE cloud_capture_downloads_017 (
    gallery_id TEXT PRIMARY KEY CHECK (length(gallery_id) > 0),
    account_id BLOB NOT NULL CHECK (typeof(account_id) = 'blob' AND length(account_id) > 0),
    title TEXT NOT NULL,
    file_extension TEXT NOT NULL,
    video INTEGER NOT NULL CHECK (video IN (0, 1)),
    created INTEGER CHECK (created IS NULL OR typeof(created) = 'integer'),
    folder TEXT NOT NULL CHECK (length(folder) > 0),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    queued_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
        CHECK (typeof(queued_at) = 'integer')
);
INSERT INTO cloud_capture_downloads_017(gallery_id, account_id, title, file_extension, video, created, folder,
    attempts, queued_at)
SELECT gallery_id, account_id, title, file_extension, CAST(video AS INTEGER),
       CAST(round((julianday(NULLIF(created, '')) - 2440587.5) * 86400000) AS INTEGER),
       folder, CAST(attempts AS INTEGER),
       COALESCE(CAST(round((julianday(queued_at) - 2440587.5) * 86400000) AS INTEGER),
                CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
FROM cloud_capture_downloads;
DROP TABLE cloud_capture_downloads;
ALTER TABLE cloud_capture_downloads_017 RENAME TO cloud_capture_downloads;

CREATE TRIGGER profiles_forget_login_pin AFTER DELETE ON profiles
BEGIN
    UPDATE consoles SET encrypted_login_pin = NULL, login_pin_profile_id = NULL
    WHERE login_pin_profile_id = old.id;
END;
CREATE TRIGGER registrations_release_console_launch AFTER DELETE ON registrations
BEGIN
    UPDATE consoles SET encrypted_login_pin = NULL, login_pin_profile_id = NULL
    WHERE id = old.console_id AND login_pin_profile_id = old.profile_id;
    UPDATE consoles SET connect_at_launch = 0
    WHERE id = old.console_id AND NOT EXISTS (SELECT 1 FROM registrations WHERE console_id = old.console_id);
END;
