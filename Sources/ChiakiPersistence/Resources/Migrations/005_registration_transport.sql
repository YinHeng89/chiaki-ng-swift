ALTER TABLE registrations ADD COLUMN remote_device_id BLOB
    CHECK(remote_device_id IS NULL OR (typeof(remote_device_id) = 'blob' AND length(remote_device_id) = 32));
