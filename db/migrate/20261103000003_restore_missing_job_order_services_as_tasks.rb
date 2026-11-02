# The multi-task migration made one task per order from the first of its services
# (job_orders_services) and dropped the others. Each service of an order that is on none of
# its tasks becomes a task of its own, with the order's job type and, for an order that had
# an old quote, a quote priced from the matching job_order_quote_services row (per_unit as
# service_price, quantity as service_quantity, price 0). Tasks are numbered after the
# order's existing ones, as the wizard does. Only orders the multi-task migration converted
# are in scope: created before their "Main Task" (all made on 2025-08-11) and still having
# exactly that one task; an order that has been worked on since is left alone. Re-running
# adds nothing: a service already on a task is not missing.
class RestoreMissingJobOrderServicesAsTasks < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      WITH missing AS (
        SELECT d.*, ROW_NUMBER() OVER (PARTITION BY d.job_order_id ORDER BY d.job_service_id) AS rn
        FROM (
          SELECT DISTINCT os.job_order_id, os.job_service_id, o.job_type_id
          FROM job_orders_services os
          JOIN job_orders o ON o.id = os.job_order_id
          JOIN job_tasks main ON main.job_order_id = o.id AND main.title = 'Main Task'
          WHERE main.created_at::date = DATE '2025-08-11'
            AND o.created_at < main.created_at
            AND (SELECT COUNT(*) FROM job_tasks t WHERE t.job_order_id = o.id) = 1
            AND EXISTS (SELECT 1 FROM job_services js WHERE js.id = os.job_service_id)
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
        RETURNING id, job_order_id, job_service_id
      )
      INSERT INTO job_task_quotes (job_task_id, price, service_price, service_quantity, created_at, updated_at)
      SELECT DISTINCT ON (nt.id) nt.id, 0, s.per_unit, s.quantity, NOW(), NOW()
      FROM new_tasks nt
      JOIN job_orders o ON o.id = nt.job_order_id
      JOIN job_order_quote_services s
        ON s.job_order_quote_id = o.job_order_quote_id AND s.job_service_id = nt.job_service_id
      ORDER BY nt.id, s.id
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the restored tasks are not marked, so they cannot be told from tasks added since"
  end
end
