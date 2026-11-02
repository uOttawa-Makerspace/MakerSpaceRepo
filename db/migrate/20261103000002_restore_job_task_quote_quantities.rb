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
#     first quote service (that price, that quantity with the fraction dropped).
# A quote edited afterwards, or holding any other values, is left alone.
class RestoreJobTaskQuoteQuantities < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE job_task_quotes q
      SET service_price = s.per_unit,
          service_quantity = s.quantity
      FROM job_tasks t
      JOIN job_orders o ON o.id = t.job_order_id
      JOIN job_order_quote_services f ON f.id = (
        SELECT MIN(x.id) FROM job_order_quote_services x WHERE x.job_order_quote_id = o.job_order_quote_id
      )
      JOIN job_order_quote_services s
        ON s.job_order_quote_id = o.job_order_quote_id AND s.job_service_id = t.job_service_id
      WHERE q.job_task_id = t.id
        AND t.title = 'Main Task'
        AND ABS(EXTRACT(EPOCH FROM (q.created_at - t.created_at))) < 5
        AND q.updated_at <= q.created_at + INTERVAL '5 seconds'
        AND q.service_price = f.per_unit
        AND q.service_quantity = TRUNC(f.quantity)
        AND (q.service_price, q.service_quantity) IS DISTINCT FROM (s.per_unit, s.quantity)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the values it replaces are the truncated ones; putting them back would re-introduce the loss"
  end
end
