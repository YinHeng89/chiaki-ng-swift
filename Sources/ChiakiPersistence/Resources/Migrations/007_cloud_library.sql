CREATE TABLE cloud_library_cache (
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    payload BLOB NOT NULL,
    fetched_at REAL NOT NULL,
    PRIMARY KEY(profile_id, locale)
);
