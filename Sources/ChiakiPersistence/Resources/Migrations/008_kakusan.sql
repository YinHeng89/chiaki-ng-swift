CREATE TABLE kakusan_identity (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    encrypted_seed BLOB NOT NULL,
    public_key BLOB NOT NULL CHECK (length(public_key) = 32),
    key_version INTEGER NOT NULL CHECK (key_version > 0),
    created_at REAL NOT NULL
);
CREATE TABLE kakusan_peers (
    public_key BLOB PRIMARY KEY NOT NULL CHECK (length(public_key) = 32),
    fingerprint BLOB NOT NULL CHECK (length(fingerprint) = 32),
    nickname TEXT NOT NULL CHECK (length(trim(nickname)) > 0),
    first_verified_at REAL NOT NULL,
    last_seen_at REAL NOT NULL
);
CREATE UNIQUE INDEX kakusan_peers_nickname ON kakusan_peers(nickname COLLATE NOCASE);
