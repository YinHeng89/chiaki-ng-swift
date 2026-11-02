ALTER TABLE consoles ADD COLUMN connect_at_launch INTEGER NOT NULL DEFAULT 0
    CHECK (connect_at_launch IN (0, 1));
ALTER TABLE consoles ADD COLUMN encrypted_login_pin BLOB
    CHECK (encrypted_login_pin IS NULL OR (typeof(encrypted_login_pin) = 'blob' AND length(encrypted_login_pin) > 1));
ALTER TABLE consoles ADD COLUMN login_pin_profile_id TEXT
    CHECK ((login_pin_profile_id IS NULL) = (encrypted_login_pin IS NULL));
CREATE UNIQUE INDEX consoles_connect_at_launch ON consoles(connect_at_launch) WHERE connect_at_launch = 1;
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
