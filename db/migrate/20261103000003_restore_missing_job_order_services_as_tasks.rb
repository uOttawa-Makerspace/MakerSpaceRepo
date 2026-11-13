# The multi-task migration made one task per order from the first of its services
# (job_orders_services) and dropped the others. Each service of an order that is on none of
# its tasks becomes a task of its own, with the order's job type and, for an order that had
# an old quote, a quote priced from the matching job_order_quote_services row (per_unit as
# service_price, quantity as service_quantity, price 0). Tasks are numbered after the
# order's existing ones, as the wizard does. Re-running adds nothing: a service already on a
# task is not missing.
#
# Scope: the orders the multi-task migration converted, i.e. an order created before its
# "Main Task" (all made on 2025-08-11) that still has exactly that one task. The scope is
# computed once, before anything is written, into job_order_repair_scope, and the restore,
# the notice and the final check all read it, so they cannot drift apart. An order whose Main
# Task quote was edited since the copy (updated_at more than 5 seconds after created_at) is in
# the scope table as edited and is left alone.
#
# The migration then checks its own result in the same transaction: for every order that had
# an old quote, the total JobOrder#total_price computes from the tasks must equal the old
# quote's total (service_fee + services + options + type extras). A difference in an unedited,
# in-scope order raises, naming the orders (ids only), and rolls the migration back, so the
# data it actually ran on proves the invariant. Orders outside that scope (edited, or changed
# since) that differ are only reported in a notice: a staff edit made between a backup and a
# deploy must not block the deploy.
#
# Every task and quote it inserts is recorded, as the full row, in job_task_restorations by the
# same statement. down deletes exactly those rows, and only when each is still as it was
# inserted and has nothing attached to it (no task options, quote options, other quotes or
# uploaded files); otherwise it raises with the ids, deletes nothing and keeps the record.
# The record table is dropped only after every recorded row is removed.
class RestoreMissingJobOrderServicesAsTasks < ActiveRecord::Migration[8.1]
  RECORD = "job_task_restorations"

  def up
    create_table RECORD, primary_key: :job_task_id, id: :bigint, default: nil, if_not_exists: true do |t|
      t.bigint :job_task_quote_id
      t.jsonb :task_row, null: false
      t.jsonb :quote_row
      t.datetime :archived_at, null: false, default: -> { "now()" }
    end

    execute <<~SQL
      DROP TABLE IF EXISTS job_order_repair_scope
    SQL
    execute <<~SQL
      CREATE TEMP TABLE job_order_repair_scope ON COMMIT DROP AS
      SELECT o.id AS job_order_id, o.job_type_id, o.job_order_quote_id,
             EXISTS (
               SELECT 1 FROM job_task_quotes mq
               WHERE mq.job_task_id = main.id AND mq.updated_at > mq.created_at + INTERVAL '5 seconds'
             ) AS edited
      FROM job_orders o
      JOIN job_tasks main ON main.job_order_id = o.id AND main.title = 'Main Task'
      WHERE main.created_at::date = DATE '2025-08-11'
        AND o.created_at < main.created_at
        AND (SELECT COUNT(*) FROM job_tasks t WHERE t.job_order_id = o.id) = 1
    SQL

    execute <<~SQL
      DO $$
      BEGIN
        RAISE NOTICE 'orders with missing services skipped, Main Task quote edited since the copy: %',
          (SELECT COUNT(DISTINCT os.job_order_id)
           FROM job_orders_services os
           JOIN job_order_repair_scope sc ON sc.job_order_id = os.job_order_id AND sc.edited
           WHERE NOT EXISTS (
             SELECT 1 FROM job_tasks t
             WHERE t.job_order_id = os.job_order_id AND t.job_service_id = os.job_service_id
           ));
      END $$
    SQL

    execute <<~SQL
      WITH missing AS (
        SELECT d.*, ROW_NUMBER() OVER (PARTITION BY d.job_order_id ORDER BY d.job_service_id) AS rn
        FROM (
          SELECT DISTINCT os.job_order_id, os.job_service_id, sc.job_type_id
          FROM job_orders_services os
          JOIN job_order_repair_scope sc ON sc.job_order_id = os.job_order_id AND NOT sc.edited
          WHERE EXISTS (SELECT 1 FROM job_services js WHERE js.id = os.job_service_id)
            AND NOT EXISTS (
              SELECT 1 FROM job_tasks t
              WHERE t.job_order_id = os.job_order_id AND t.job_service_id = os.job_service_id
            )
        ) d
      ),
      new_tasks AS (
        INSERT INTO job_tasks (job_order_id, job_type_id, job_service_id, title, created_at, updated_at)
        SELECT m.job_order_id, m.job_type_id, m.job_service_id,
               'Task #' || (GREATEST(
                 COALESCE((SELECT MAX(SUBSTRING(t.title FROM 'Task ([0-9]+)')::integer)
                           FROM job_tasks t WHERE t.job_order_id = m.job_order_id), 0),
                 (SELECT COUNT(*) FROM job_tasks t WHERE t.job_order_id = m.job_order_id)
               ) + m.rn),
               NOW(), NOW()
        FROM missing m
        RETURNING id, job_order_id, job_service_id, to_jsonb(job_tasks) AS row_data
      ),
      new_quotes AS (
        INSERT INTO job_task_quotes (job_task_id, price, service_price, service_quantity, created_at, updated_at)
        SELECT DISTINCT ON (nt.id) nt.id, 0, s.per_unit, s.quantity, NOW(), NOW()
        FROM new_tasks nt
        JOIN job_orders o ON o.id = nt.job_order_id
        JOIN job_order_quote_services s
          ON s.job_order_quote_id = o.job_order_quote_id AND s.job_service_id = nt.job_service_id
        ORDER BY nt.id, s.id
        RETURNING id, job_task_id, to_jsonb(job_task_quotes) AS row_data
      )
      INSERT INTO #{RECORD} (job_task_id, job_task_quote_id, task_row, quote_row)
      SELECT nt.id, nq.id, nt.row_data, nq.row_data
      FROM new_tasks nt LEFT JOIN new_quotes nq ON nq.job_task_id = nt.id
    SQL

    execute <<~SQL
      DO $$
      DECLARE
        checked bigint;
        in_scope_differing bigint[];
        out_of_scope_differing bigint[];
      BEGIN
        CREATE TEMP TABLE job_order_repair_totals ON COMMIT DROP AS
        SELECT o.id AS order_id,
               COALESCE(qt.service_fee, 0)
                 + COALESCE((SELECT SUM(s.per_unit * s.quantity) FROM job_order_quote_services s WHERE s.job_order_quote_id = qt.id), 0)
                 + COALESCE((SELECT SUM(x.amount) FROM job_order_quote_options x WHERE x.job_order_quote_id = qt.id), 0)
                 + COALESCE((SELECT SUM(e.price) FROM job_order_quote_type_extras e WHERE e.job_order_quote_id = qt.id), 0) AS old_total,
               COALESCE((SELECT SUM(COALESCE(q.price, 0) + COALESCE(q.service_price, 0) * COALESCE(q.service_quantity, 0)
                                    + COALESCE((SELECT SUM(COALESCE(p.price, 0)) FROM job_task_quote_options p WHERE p.job_task_quote_id = q.id), 0))
                         FROM job_tasks t JOIN job_task_quotes q ON q.job_task_id = t.id
                         WHERE t.job_order_id = o.id), 0)
                 + COALESCE((SELECT SUM(COALESCE(li.price, 0)) FROM job_quote_line_items li WHERE li.job_order_id = o.id), 0) AS new_total,
               (sc.job_order_id IS NOT NULL AND NOT sc.edited) AS in_scope
        FROM job_orders o
        JOIN job_order_quotes qt ON qt.id = o.job_order_quote_id
        LEFT JOIN job_order_repair_scope sc ON sc.job_order_id = o.id;

        SELECT COUNT(*) INTO checked FROM job_order_repair_totals WHERE in_scope;
        SELECT ARRAY_AGG(order_id ORDER BY order_id) INTO in_scope_differing
          FROM job_order_repair_totals WHERE in_scope AND old_total <> new_total;
        SELECT ARRAY_AGG(order_id ORDER BY order_id) INTO out_of_scope_differing
          FROM job_order_repair_totals WHERE NOT in_scope AND old_total <> new_total;

        RAISE NOTICE 'old-quote orders checked in scope: %', checked;
        IF out_of_scope_differing IS NOT NULL THEN
          RAISE NOTICE '% old-quote orders outside the repair scope differ from their old quote: order ids %',
            ARRAY_LENGTH(out_of_scope_differing, 1), out_of_scope_differing;
        END IF;
        IF in_scope_differing IS NOT NULL THEN
          RAISE EXCEPTION '% old-quote orders do not total the same as their old quote after the restore: order ids %',
            ARRAY_LENGTH(in_scope_differing, 1), in_scope_differing;
        END IF;
        DROP TABLE job_order_repair_totals;
      END $$
    SQL
    execute <<~SQL
      DROP TABLE job_order_repair_scope
    SQL
  end

  # Deletes the recorded tasks and quotes, all or none. A recorded row that was edited since,
  # is gone, or has anything attached makes it raise (ids only) with nothing changed.
  def down
    unless table_exists?(RECORD)
      raise "#{RECORD} is missing: this database ran a version of the migration that did not record its rows, " \
            "so they cannot be removed; nothing was changed"
    end

    blocked = select_values(<<~SQL.squish)
      SELECT r.job_task_id FROM #{RECORD} r
      WHERE NOT (
        EXISTS (SELECT 1 FROM job_tasks t WHERE t.id = r.job_task_id AND to_jsonb(t) = r.task_row)
        AND (SELECT COUNT(*) FROM job_task_quotes q WHERE q.job_task_id = r.job_task_id) = (r.job_task_quote_id IS NOT NULL)::int
        AND (r.job_task_quote_id IS NULL
             OR EXISTS (SELECT 1 FROM job_task_quotes q WHERE q.id = r.job_task_quote_id AND to_jsonb(q) = r.quote_row))
        AND NOT EXISTS (SELECT 1 FROM job_task_options o WHERE o.job_task_id = r.job_task_id)
        AND NOT EXISTS (SELECT 1 FROM job_task_quote_options x WHERE x.job_task_quote_id = r.job_task_quote_id)
        AND NOT EXISTS (SELECT 1 FROM active_storage_attachments a WHERE a.record_type = 'JobTask' AND a.record_id = r.job_task_id)
      )
      ORDER BY r.job_task_id
    SQL
    if blocked.any?
      raise "Cannot remove the restored job tasks: tasks #{blocked.inspect} were edited since, are gone or have " \
            "something attached; nothing was changed and #{RECORD} was kept"
    end

    execute "DELETE FROM job_task_quotes WHERE id IN (SELECT job_task_quote_id FROM #{RECORD})"
    execute "DELETE FROM job_tasks WHERE id IN (SELECT job_task_id FROM #{RECORD})"
    execute "DROP TABLE #{RECORD}"
  end
end
