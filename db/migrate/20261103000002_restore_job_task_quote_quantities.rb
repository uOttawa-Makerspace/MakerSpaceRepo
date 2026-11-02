# The multi-task migration (SupportMultipleTasksPerJobOrder) copied each old quote's first
# service into the order's task quote while job_task_quotes.service_quantity had no scale,
# so a fractional quantity lost its fraction (0.5 became 0, 60.5 became 60). It also copied
# the quote's first service rather than the service the task is for. This restores the
# service price and quantity from the matching job_order_quote_services row.
#
# Only quotes still in the state that copy left are repaired:
#   - the task is the "Main Task" the copy created, and its quote was created with it;
#   - the quote was never edited since (updated_at within 5 seconds of created_at);
#   - its service price and quantity are exactly what the copy produced from the order's
#     first quote service (that price, that quantity with the fraction dropped, truncated or
#     rounded to a whole number).
# The service restored from is the quote service for the task's own job service, lowest id
# first; a task with no service, or one the quote does not list, is restored from the
# quote's first service, which is what the copy used. A quote edited afterwards, or holding
# any other values, is left alone.
class RestoreJobTaskQuoteQuantities < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE job_task_quotes q
      SET service_price = c.per_unit,
          service_quantity = c.quantity
      FROM (
        SELECT DISTINCT ON (q2.id) q2.id AS quote_id, s.per_unit, s.quantity
        FROM job_task_quotes q2
        JOIN job_tasks t ON t.id = q2.job_task_id
        JOIN job_orders o ON o.id = t.job_order_id
        JOIN job_order_quote_services f ON f.id = (
          SELECT MIN(x.id) FROM job_order_quote_services x WHERE x.job_order_quote_id = o.job_order_quote_id
        )
        JOIN job_order_quote_services s
          ON s.job_order_quote_id = o.job_order_quote_id
         AND (s.job_service_id = t.job_service_id OR s.id = f.id)
        WHERE t.title = 'Main Task'
          AND ABS(EXTRACT(EPOCH FROM (q2.created_at - t.created_at))) < 5
          AND q2.updated_at <= q2.created_at + INTERVAL '5 seconds'
          AND q2.service_price = f.per_unit
          AND q2.service_quantity IN (TRUNC(f.quantity), ROUND(f.quantity))
        ORDER BY q2.id, (t.job_service_id IS NOT NULL AND s.job_service_id = t.job_service_id) DESC, s.id
      ) c
      WHERE q.id = c.quote_id
        AND (q.service_price, q.service_quantity) IS DISTINCT FROM (c.per_unit, c.quantity)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the values it replaces are the truncated ones; putting them back would re-introduce the loss"
  end
end
