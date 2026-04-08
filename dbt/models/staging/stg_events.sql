SELECT
    event_id,
    event_timestamp,
    event_type,
    user_id,
    department_code,
    resource_type,
    resource_id,
    duration_ms,
    metadata
FROM {{ source('openinsight', 'fct_events') }}
