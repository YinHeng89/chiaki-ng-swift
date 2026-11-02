CREATE TABLE cloud_capture_downloads (
    gallery_id TEXT PRIMARY KEY CHECK (length(gallery_id) > 0),
    account_id BLOB NOT NULL CHECK (typeof(account_id) = 'blob' AND length(account_id) > 0),
    title TEXT NOT NULL,
    file_extension TEXT NOT NULL,
    video INTEGER NOT NULL CHECK (video IN (0, 1)),
    created TEXT NOT NULL,
    folder TEXT NOT NULL CHECK (length(folder) > 0),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    queued_at TEXT NOT NULL
);
