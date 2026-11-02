CREATE TABLE profiles (
    id TEXT NOT NULL PRIMARY KEY,
    display_name TEXT NOT NULL CHECK(length(trim(display_name)) > 0),
    auth_method TEXT NOT NULL CHECK(auth_method IN ('npsso', 'account_id')),

    psn_account_id BLOB NOT NULL CHECK(typeof(psn_account_id) = 'blob' AND length(psn_account_id) = 8),
    psn_online_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TABLE consoles (
    id TEXT NOT NULL PRIMARY KEY,
    hardware_id TEXT UNIQUE,
    name TEXT NOT NULL,
    generation TEXT NOT NULL CHECK (generation IN ('ps4', 'ps5')),
    last_address TEXT
);
CREATE TABLE registrations (
    id TEXT NOT NULL PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    console_id TEXT NOT NULL REFERENCES consoles(id) ON DELETE CASCADE,
    encrypted_credentials BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (profile_id, console_id)
);
CREATE INDEX registrations_by_console ON registrations(console_id);
CREATE TABLE profile_tokens (
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    credential_kind TEXT NOT NULL CHECK(credential_kind IN ('remote_play', 'mobile_sso')),
    encrypted_tokens BLOB NOT NULL,
    key_version INTEGER NOT NULL CHECK(key_version > 0),
    expires_at TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY(profile_id, credential_kind)
);
CREATE TABLE settings (key TEXT PRIMARY KEY, value_json TEXT NOT NULL);
