CREATE TABLE account_context (
    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    country TEXT,
    language TEXT,
    legal_country TEXT,
    locale TEXT,
    age INTEGER CHECK (age IS NULL OR (typeof(age) = 'integer' AND age >= 0)),
    is_child INTEGER CHECK (is_child IS NULL OR is_child IN (0, 1)),
    issued_at INTEGER CHECK (issued_at IS NULL OR typeof(issued_at) = 'integer'),
    CHECK ((country IS NULL) = (language IS NULL))
) WITHOUT ROWID;

INSERT INTO account_context(profile_id, country, language, legal_country, locale, age, is_child, issued_at)
SELECT profiles.id,
       CASE WHEN json_type(region.value_json, '$.country') = 'text' AND json_type(region.value_json, '$.language') = 'text'
            THEN json_extract(region.value_json, '$.country') END,
       CASE WHEN json_type(region.value_json, '$.country') = 'text' AND json_type(region.value_json, '$.language') = 'text'
            THEN json_extract(region.value_json, '$.language') END,
       CASE WHEN json_type(context.value_json, '$.legalCountry') = 'text'
            THEN json_extract(context.value_json, '$.legalCountry') END,
       CASE WHEN json_type(context.value_json, '$.locale') = 'text'
            THEN json_extract(context.value_json, '$.locale') END,
       CASE WHEN json_type(context.value_json, '$.age') = 'integer' AND json_extract(context.value_json, '$.age') >= 0
            THEN json_extract(context.value_json, '$.age') END,
       CASE json_type(context.value_json, '$.isChild') WHEN 'true' THEN 1 WHEN 'false' THEN 0 END,
       CASE WHEN json_type(context.value_json, '$.issuedAtMs') = 'integer'
            THEN json_extract(context.value_json, '$.issuedAtMs') END
FROM profiles
LEFT JOIN settings AS region
    ON region.key = 'accounts.region.v1.' || profiles.id AND json_valid(region.value_json)
LEFT JOIN settings AS context
    ON context.key = 'accounts.context.v1.' || profiles.id AND json_valid(context.value_json)
WHERE region.key IS NOT NULL OR context.key IS NOT NULL;

DELETE FROM settings WHERE key LIKE 'accounts.region.v1.%' OR key LIKE 'accounts.context.v1.%';
