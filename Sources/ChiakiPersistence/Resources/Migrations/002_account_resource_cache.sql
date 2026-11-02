CREATE TABLE account_resource_cache (
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    resource TEXT NOT NULL CHECK(resource IN ('profile', 'avatar', 'pscloud')),
    payload BLOB NOT NULL,
    source_url TEXT,
    fetched_at REAL NOT NULL,
    expires_at REAL NOT NULL,
    PRIMARY KEY(profile_id, resource)
);
