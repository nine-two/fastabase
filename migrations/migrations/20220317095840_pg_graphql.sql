-- migrate:up
create schema if not exists graphql_public;

-- obsolete signature: https://github.com/supabase/infrastructure/pull/5524/files
drop function if exists graphql_public.graphql(text, text, jsonb);
-- GraphQL Placeholder Entrypoint
create or replace function graphql_public.graphql(
    "operationName" text default null,
    query text default null,
    variables jsonb default null,
    extensions jsonb default null
)
    returns jsonb
    language plpgsql
as $$
    DECLARE
        server_version float;
    BEGIN
        server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

        IF server_version >= 14 THEN
            RETURN jsonb_build_object(
                'data', null::jsonb,
                'errors', array['pg_graphql extension is not enabled.']
            );
        ELSE
            RETURN jsonb_build_object(
                'data', null::jsonb,
                'errors', array['pg_graphql is only available on projects running Postgres 14 onwards.']
            );
        END IF;
    END;
$$;

grant usage on schema graphql_public to postgres, anon, authenticated, service_role;
alter default privileges in schema graphql_public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema graphql_public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema graphql_public grant all on sequences to postgres, anon, authenticated, service_role;

alter default privileges in schema graphql_public grant all
    on sequences to postgres, anon, authenticated, service_role;
alter default privileges in schema graphql_public grant all
    on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema graphql_public grant all
    on functions to postgres, anon, authenticated, service_role;

-- Trigger upon enabling pg_graphql
CREATE OR REPLACE FUNCTION extensions.grant_pg_graphql_access()
RETURNS event_trigger
LANGUAGE plpgsql
AS $func$
    DECLARE
    func_is_graphql_resolve bool;
    BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant all on function graphql.resolve to postgres, anon, authenticated, service_role;

        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            SELECT graphql.resolve(query, coalesce(variables, '{}'));
        $$;

        grant execute on function graphql.resolve to postgres, anon, authenticated, service_role;
    END IF;

    END;
$func$;

DROP EVENT TRIGGER IF EXISTS issue_pg_graphql_access;
-- CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end WHEN TAG in ('CREATE FUNCTION')
-- EXECUTE PROCEDURE extensions.grant_pg_graphql_access();
COMMENT ON FUNCTION extensions.grant_pg_graphql_access IS 'Grants access to pg_graphql';

-- Trigger upon dropping the pg_graphql extension
CREATE OR REPLACE FUNCTION extensions.set_graphql_placeholder()
RETURNS event_trigger
LANGUAGE plpgsql
AS $func$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'data', null::jsonb,
                        'errors', array['pg_graphql extension is not enabled.']
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'data', null::jsonb,
                        'errors', array['pg_graphql is only available on projects running Postgres 14 onwards.']
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$func$;

DROP EVENT TRIGGER IF EXISTS issue_graphql_placeholder;
-- CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop WHEN TAG in ('DROP EXTENSION')
-- EXECUTE PROCEDURE extensions.set_graphql_placeholder();
COMMENT ON FUNCTION extensions.set_graphql_placeholder IS 'Reintroduces placeholder function for graphql_public.graphql';

-- migrate:down
