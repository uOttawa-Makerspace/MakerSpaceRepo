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
#
# Each quote it changes is first copied, with its old and new price and quantity, into
# job_task_quote_repairs by the same statement, so down puts the old values back (only where
# the quote still holds the repaired ones) and drops the table once every one is back.
class RestoreJobTaskQuoteQuantities < ActiveRecord::Migration[8.1]
  ARCHIVE = "job_task_quote_repairs"

  def up
    create_table ARCHIVE, id: false, if_not_exists: true do |t|
      t.bigint :job_task_quote_id, null: false, primary_key: true
      t.decimal :old_service_price, precision: 10, scale: 2
      t.decimal :old_service_quantity, precision: 10, scale: 4
      t.decimal :new_service_price, precision: 10, scale: 2
      t.decimal :new_service_quantity, precision: 10, scale: 4
      t.jsonb :row_data, null: false
      t.datetime :archived_at, null: false, default: -> { "now()" }
    end

    execute <<~SQL
      WITH c AS (
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
      ), changing AS (
        SELECT q.id, q.service_price AS old_price, q.service_quantity AS old_quantity,
               c.per_unit, c.quantity, to_jsonb(q) AS row_data
        FROM job_task_quotes q JOIN c ON c.quote_id = q.id
        WHERE (q.service_price, q.service_quantity) IS DISTINCT FROM (c.per_unit, c.quantity)
        FOR UPDATE OF q
      ), archived AS (
        INSERT INTO #{ARCHIVE} (job_task_quote_id, old_service_price, old_service_quantity,
                                new_service_price, new_service_quantity, row_data)
        SELECT id, old_price, old_quantity, per_unit, quantity, row_data FROM changing
        RETURNING 1
      )
      UPDATE job_task_quotes q
      SET service_price = changing.per_unit,
          service_quantity = changing.quantity
      FROM changing
      WHERE q.id = changing.id
    SQL
  end

  # Puts the old price and quantity back on every quote that still holds the repaired ones
  # (a quote edited since is left alone). Raises, changing nothing, unless every archived
  # quote is put back; the archive is dropped only after that.
  def down
    unless table_exists?(ARCHIVE)
      raise "#{ARCHIVE} is missing: this database ran a version of the migration that did not record its changes, " \
            "so they cannot be restored; nothing was changed"
    end

    archived = select_value("SELECT COUNT(*) FROM #{ARCHIVE}").to_i
    restored = execute(<<~SQL.squish).cmd_tuples
      UPDATE job_task_quotes q
      SET service_price = a.old_service_price, service_quantity = a.old_service_quantity
      FROM #{ARCHIVE} a
      WHERE q.id = a.job_task_quote_id
        AND q.service_price IS NOT DISTINCT FROM a.new_service_price
        AND q.service_quantity IS NOT DISTINCT FROM a.new_service_quantity
    SQL
    if restored != archived
      raise "Cannot restore job task quotes: put back #{restored} of #{archived} (the others were edited since or are gone); " \
            "nothing was changed and #{ARCHIVE} was kept"
    end

    execute "DROP TABLE #{ARCHIVE}"
  end
end
