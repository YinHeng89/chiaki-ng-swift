CREATE TABLE datacenter_measurements (
    service TEXT NOT NULL CHECK (service IN ('psnow', 'pscloud')),
    name TEXT NOT NULL CHECK (
        length(name) > 0 AND length(CAST(name AS BLOB)) <= 256 AND name <> 'Auto'
        AND NOT name GLOB ('*[' || char(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
            21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 127) || ']*')
    ),
    round_trip_ms INTEGER NOT NULL CHECK (typeof(round_trip_ms) = 'integer' AND round_trip_ms > 0),
    samples_ms TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(samples_ms) AND json_type(samples_ms) = 'array'),
    mtu_in INTEGER NOT NULL DEFAULT 0 CHECK (typeof(mtu_in) = 'integer'),
    mtu_out INTEGER NOT NULL DEFAULT 0 CHECK (typeof(mtu_out) = 'integer'),
    port INTEGER NOT NULL DEFAULT 0 CHECK (typeof(port) = 'integer'),
    public_address TEXT NOT NULL DEFAULT '',
    max_bandwidth INTEGER NOT NULL DEFAULT 0 CHECK (typeof(max_bandwidth) = 'integer'),
    measured_at INTEGER NOT NULL CHECK (typeof(measured_at) = 'integer'),
    bandwidth_kbps INTEGER CHECK (bandwidth_kbps IS NULL OR (typeof(bandwidth_kbps) = 'integer' AND bandwidth_kbps > 0)),
    bandwidth_measured_at INTEGER
        CHECK (bandwidth_measured_at IS NULL OR typeof(bandwidth_measured_at) = 'integer'),
    bandwidth_round_trip_ms INTEGER
        CHECK (bandwidth_round_trip_ms IS NULL OR typeof(bandwidth_round_trip_ms) = 'integer'),
    CHECK ((bandwidth_kbps IS NULL) = (bandwidth_measured_at IS NULL)
        AND (bandwidth_kbps IS NULL) = (bandwidth_round_trip_ms IS NULL)),
    PRIMARY KEY (service, name)
) WITHOUT ROWID;

WITH lists(service, path) AS (
    VALUES ('psnow', '$.psNowMeasurements'), ('pscloud', '$.psCloudMeasurements')
),
stored AS (
    SELECT lists.service AS service,
           json_extract(entry.value, '$.name') AS name,
           CAST(json_extract(entry.value, '$.rttMs') AS INTEGER) AS round_trip_ms,
           CASE WHEN json_type(entry.value, '$.rttsMs') = 'array'
                THEN json_extract(entry.value, '$.rttsMs') ELSE '[]' END AS samples_ms,
           CAST(COALESCE(json_extract(entry.value, '$.mtuIn'), 0) AS INTEGER) AS mtu_in,
           CAST(COALESCE(json_extract(entry.value, '$.mtuOut'), 0) AS INTEGER) AS mtu_out,
           CAST(COALESCE(json_extract(entry.value, '$.port'), 0) AS INTEGER) AS port,
           COALESCE(json_extract(entry.value, '$.publicIP'), '') AS public_address,
           CAST(COALESCE(json_extract(entry.value, '$.maxBandwidth'), 0) AS INTEGER) AS max_bandwidth,
           CAST(round((json_extract(entry.value, '$.measuredAt') + 978307200) * 1000) AS INTEGER) AS measured_at,
           CAST(json_extract(entry.value, '$.bandwidthKbps') AS INTEGER) AS bandwidth_kbps,
           json_extract(entry.value, '$.bandwidthMeasuredAt') AS bandwidth_measured_at,
           CAST(COALESCE(json_extract(entry.value, '$.bandwidthRttMs'), 0) AS INTEGER) AS bandwidth_round_trip_ms
    FROM settings
    JOIN lists
    JOIN json_each(settings.value_json, lists.path) AS entry
    WHERE settings.key = 'cloud.datacenters.v1' AND json_valid(settings.value_json)
      AND json_type(settings.value_json, lists.path) = 'array'
),
valid AS (
    SELECT * FROM stored
    WHERE typeof(name) = 'text' AND length(name) > 0 AND length(CAST(name AS BLOB)) <= 256 AND name <> 'Auto'
      AND NOT name GLOB ('*[' || char(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
          21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 127) || ']*')
      AND round_trip_ms > 0 AND measured_at IS NOT NULL
),
unique_names AS (
    SELECT *, row_number() OVER (PARTITION BY service, name ORDER BY round_trip_ms) AS copy
    FROM valid
),
ranked AS (
    SELECT *, row_number() OVER (PARTITION BY service ORDER BY round_trip_ms, name) AS rank
    FROM unique_names WHERE copy = 1
)
INSERT INTO datacenter_measurements(
    service, name, round_trip_ms, samples_ms, mtu_in, mtu_out, port, public_address, max_bandwidth, measured_at,
    bandwidth_kbps, bandwidth_measured_at, bandwidth_round_trip_ms
)
SELECT service, name, round_trip_ms, samples_ms, mtu_in, mtu_out, port, public_address, max_bandwidth, measured_at,
       CASE WHEN bandwidth_kbps > 0 AND bandwidth_measured_at IS NOT NULL THEN bandwidth_kbps END,
       CASE WHEN bandwidth_kbps > 0 AND bandwidth_measured_at IS NOT NULL
            THEN CAST(round((bandwidth_measured_at + 978307200) * 1000) AS INTEGER) END,
       CASE WHEN bandwidth_kbps > 0 AND bandwidth_measured_at IS NOT NULL THEN bandwidth_round_trip_ms END
FROM ranked WHERE rank <= 64;

UPDATE settings
SET value_json = json_remove(value_json, '$.psNowMeasurements', '$.psCloudMeasurements')
WHERE key = 'cloud.datacenters.v1' AND json_valid(value_json);
