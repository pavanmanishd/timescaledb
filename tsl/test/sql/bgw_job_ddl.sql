-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

-- Test for DDL-like functionality

\c :TEST_DBNAME :ROLE_SUPERUSER
CREATE OR REPLACE FUNCTION insert_job(
       application_name NAME,
       job_type NAME,
       schedule_interval INTERVAL,
       max_runtime INTERVAL,
       retry_period INTERVAL,
       owner regrole DEFAULT CURRENT_ROLE::regrole,
       scheduled BOOL DEFAULT true,
       fixed_schedule BOOL DEFAULT false
) RETURNS INT LANGUAGE SQL SECURITY DEFINER AS
$$
  INSERT INTO _timescaledb_config.bgw_job(application_name,schedule_interval,max_runtime,max_retries,
  retry_period,proc_name,proc_schema,owner,scheduled,fixed_schedule)
  VALUES($1,$3,$4,5,$5,$2,'public',$6,$7,$8) RETURNING id;
$$;

CREATE USER another_user;

SET ROLE another_user;
SELECT insert_job('another_one', 'bgw_test_job_1', INTERVAL '100ms', INTERVAL '100s', INTERVAL '1s') AS job_id \gset

SELECT proc_name, owner FROM _timescaledb_config.bgw_job WHERE id = :job_id;

-- Test that reassigning to another user privileges does not work for
-- a normal user. We test both users with superuser privileges and
-- default permissions.
\set ON_ERROR_STOP 0
REASSIGN OWNED BY another_user TO :ROLE_CLUSTER_SUPERUSER;
REASSIGN OWNED BY another_user TO :ROLE_DEFAULT_PERM_USER;
\set ON_ERROR_STOP 1

RESET ROLE;

-- Test that renaming a user changes keeps the job assigned to that user.
ALTER USER another_user RENAME TO renamed_user;
SELECT proc_name, owner FROM _timescaledb_config.bgw_job WHERE id = :job_id;

\set VERBOSITY default
\set ON_ERROR_STOP 0

-- Test that dropping a user owning a job fails.
DROP USER renamed_user;
SELECT proc_name, owner FROM _timescaledb_config.bgw_job WHERE id = :job_id;

-- Test that re-assigning objects owned by an unknown user still fails
REASSIGN OWNED BY renamed_user, unknown_user TO :ROLE_DEFAULT_PERM_USER;
SELECT proc_name, owner FROM _timescaledb_config.bgw_job WHERE id = :job_id;

\set ON_ERROR_STOP 1

-- Test that reassigning the owned job actually changes the owner of
-- the job.
START TRANSACTION;
REASSIGN OWNED BY renamed_user TO :ROLE_DEFAULT_PERM_USER;
SELECT proc_name, owner FROM _timescaledb_config.bgw_job WHERE id = :job_id;
ROLLBACK;

-- Test that reassigning to postgres works
REASSIGN OWNED BY renamed_user TO :ROLE_CLUSTER_SUPERUSER;
SELECT proc_name, owner FROM _timescaledb_config.bgw_job WHERE id = :job_id;

-- Dropping the user now should work.
DROP USER renamed_user;

-- Test that moving a procedure to a new schema updates bgw_job.proc_schema.
CREATE SCHEMA frugal;
CREATE PROCEDURE some_magic(job_id INT, config jsonb) LANGUAGE plpgsql AS $$
BEGIN
  RAISE NOTICE 'done';
END;
$$;

SELECT insert_job('schema_job', 'some_magic', INTERVAL '100ms', INTERVAL '100s', INTERVAL '1s') AS schema_job_id \gset
SELECT proc_schema, proc_name FROM _timescaledb_config.bgw_job WHERE id = :schema_job_id;

ALTER PROCEDURE some_magic SET SCHEMA frugal;
SELECT proc_schema, proc_name FROM _timescaledb_config.bgw_job WHERE id = :schema_job_id;

DELETE FROM _timescaledb_config.bgw_job WHERE id = :schema_job_id;
DROP PROCEDURE frugal.some_magic;
DROP SCHEMA frugal;

DELETE FROM _timescaledb_config.bgw_job WHERE id = :job_id;

