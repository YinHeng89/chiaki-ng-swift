CREATE TABLE input_configuration (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    version INTEGER NOT NULL CHECK (version > 0),
    payload TEXT NOT NULL
);
