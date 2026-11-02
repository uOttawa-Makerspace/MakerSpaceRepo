# The print order system (print_orders, 2019-2022) preceded job orders. Each print order is
# imported as a closed job order so the history is in one place. Nothing is deleted and no
# file is copied: print_orders and its attachments stay, and the new task's attachments
# point at the same blobs.
#
# Each print order becomes
#   - a job order (same user, created_at/updated_at, comments split into user_comments and
#     staff_comments, assigned_staff_id where that user exists), with legacy_print_order_id
#     set to the print order's id;
#   - one task of job type "3D Print" (order_type 0) or "Laser Cut" (order_type 1), titled
#     with the file name, holding the uploaded file (user_files) and the staff's final files
#     and PDF form (staff_files);
#   - one task quote whose price is the old quote rounded to cents (0 when there was none);
#   - one status: Declined when approved is false, otherwise Picked-Up. Both close an order.
#
# order_type maps explicitly (0 = 3D Print, 1 = Laser Cut) and the migration stops on any other
# value. A print order whose user does not exist is not imported (its count is raised as a
# NOTICE) so no order is left without an owner. Re-running imports only the print orders that
# are not imported yet.
class ImportPrintOrdersAsJobOrders < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM print_orders) AND (
          (SELECT COUNT(*) FROM job_types WHERE name IN ('3D Print', 'Laser Cut')) <> 2 OR
          (SELECT COUNT(*) FROM job_statuses WHERE name IN ('Declined', 'Picked-Up')) <> 2
        ) THEN
          RAISE EXCEPTION 'job types "3D Print" and "Laser Cut" and statuses "Declined" and "Picked-Up" are required';
        END IF;
        IF EXISTS (SELECT 1 FROM print_orders WHERE order_type IS NULL OR order_type NOT IN (0, 1)) THEN
          RAISE EXCEPTION 'print_orders.order_type must be 0 (3D print) or 1 (laser cut)';
        END IF;
        RAISE NOTICE 'print orders skipped, owner not found: %',
          (SELECT COUNT(*) FROM print_orders p
           WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p.user_id)
             AND NOT EXISTS (SELECT 1 FROM job_orders jo WHERE jo.legacy_print_order_id = p.id));
      END $$
    SQL

    execute <<~SQL
      INSERT INTO job_orders
        (legacy_print_order_id, user_id, job_type_id, assigned_staff_id, user_comments, staff_comments,
         is_deleted, created_at, updated_at)
      SELECT p.id, u.id,
             (SELECT jt.id FROM job_types jt WHERE jt.name = CASE p.order_type WHEN 0 THEN '3D Print' WHEN 1 THEN 'Laser Cut' END),
             (SELECT u.id FROM users u WHERE u.id = p.staff_id),
             NULLIF(CONCAT_WS(E'\\n', NULLIF(p.comments, ''), NULLIF(p.comments_box, '')), ''),
             NULLIF(CONCAT_WS(E'\\n', NULLIF(p.staff_comments, ''), NULLIF(p.comments_for_staff, '')), ''),
             FALSE, p.created_at, p.updated_at
      FROM print_orders p
      JOIN users u ON u.id = p.user_id
      WHERE NOT EXISTS (SELECT 1 FROM job_orders jo WHERE jo.legacy_print_order_id = p.id)
      ORDER BY p.id
    SQL

    execute <<~SQL
      INSERT INTO job_tasks (job_order_id, job_type_id, title, created_at, updated_at)
      SELECT jo.id, jo.job_type_id,
             COALESCE(NULLIF(p.file_file_name, ''),
                      (SELECT b.filename FROM active_storage_attachments a
                       JOIN active_storage_blobs b ON b.id = a.blob_id
                       WHERE a.record_type = 'PrintOrder' AND a.record_id = p.id AND a.name = 'file'
                       ORDER BY a.id LIMIT 1),
                      ''),
             p.created_at, p.updated_at
      FROM job_orders jo
      JOIN print_orders p ON p.id = jo.legacy_print_order_id
      WHERE NOT EXISTS (SELECT 1 FROM job_tasks t WHERE t.job_order_id = jo.id)
      ORDER BY jo.id
    SQL

    execute <<~SQL
      INSERT INTO job_task_quotes (job_task_id, price, service_price, service_quantity, created_at, updated_at)
      SELECT t.id, ROUND(COALESCE(p.quote, 0)::numeric, 2), 0, 1, p.created_at, p.updated_at
      FROM job_orders jo
      JOIN print_orders p ON p.id = jo.legacy_print_order_id
      JOIN job_tasks t ON t.job_order_id = jo.id
      WHERE NOT EXISTS (SELECT 1 FROM job_task_quotes q WHERE q.job_task_id = t.id)
      ORDER BY jo.id
    SQL

    execute <<~SQL
      INSERT INTO job_order_statuses (job_order_id, job_status_id, user_id, created_at, updated_at)
      SELECT jo.id,
             (SELECT js.id FROM job_statuses js WHERE js.name = CASE WHEN p.approved IS FALSE THEN 'Declined' ELSE 'Picked-Up' END),
             COALESCE(jo.assigned_staff_id, (SELECT u.id FROM users u WHERE u.id = p.user_id)),
             p.updated_at, p.updated_at
      FROM job_orders jo
      JOIN print_orders p ON p.id = jo.legacy_print_order_id
      WHERE NOT EXISTS (SELECT 1 FROM job_order_statuses s WHERE s.job_order_id = jo.id)
      ORDER BY jo.id
    SQL

    execute <<~SQL
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      SELECT DISTINCT ON (t.id, CASE a.name WHEN 'file' THEN 'user_files' ELSE 'staff_files' END, a.blob_id)
             CASE a.name WHEN 'file' THEN 'user_files' ELSE 'staff_files' END,
             'JobTask', t.id, a.blob_id, a.created_at
      FROM active_storage_attachments a
      JOIN job_orders jo ON jo.legacy_print_order_id = a.record_id
      JOIN job_tasks t ON t.job_order_id = jo.id
      WHERE a.record_type = 'PrintOrder' AND a.name IN ('file', 'final_file', 'pdf_form')
        AND NOT EXISTS (
          SELECT 1 FROM active_storage_attachments b
          WHERE b.record_type = 'JobTask' AND b.record_id = t.id
            AND b.name = CASE a.name WHEN 'file' THEN 'user_files' ELSE 'staff_files' END
            AND b.blob_id = a.blob_id
        )
      ORDER BY t.id, CASE a.name WHEN 'file' THEN 'user_files' ELSE 'staff_files' END, a.blob_id, a.id
    SQL
  end

  def down
    # Removes only what the import created, found through legacy_print_order_id: the new
    # attachment rows (the blobs and the PrintOrder rows stay), the order's quote, status and
    # task, then the order. If anything else has been added to an imported order since (more
    # tasks, quotes or statuses, options, line items, chat messages, other files), it stops
    # and leaves every row in place.
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM job_orders jo WHERE jo.legacy_print_order_id IS NOT NULL AND (
            (SELECT COUNT(*) FROM job_tasks t WHERE t.job_order_id = jo.id) <> 1
            OR (SELECT COUNT(*) FROM job_order_statuses s WHERE s.job_order_id = jo.id) <> 1
            OR EXISTS (SELECT 1 FROM chat_messages c WHERE c.job_order_id = jo.id)
            OR EXISTS (SELECT 1 FROM job_quote_line_items li WHERE li.job_order_id = jo.id)
            OR EXISTS (SELECT 1 FROM job_order_options oo WHERE oo.job_order_id = jo.id)
            OR EXISTS (SELECT 1 FROM job_services js WHERE js.job_order_id = jo.id)
            OR EXISTS (SELECT 1 FROM job_orders_services os WHERE os.job_order_id = jo.id)
            OR EXISTS (SELECT 1 FROM active_storage_attachments a WHERE a.record_type = 'JobOrder' AND a.record_id = jo.id)
            OR EXISTS (
              SELECT 1 FROM job_tasks t WHERE t.job_order_id = jo.id AND (
                (SELECT COUNT(*) FROM job_task_quotes q WHERE q.job_task_id = t.id) > 1
                OR EXISTS (SELECT 1 FROM job_task_options o WHERE o.job_task_id = t.id)
                OR EXISTS (SELECT 1 FROM job_task_quote_options qo
                           JOIN job_task_quotes q ON q.id = qo.job_task_quote_id WHERE q.job_task_id = t.id)
                OR EXISTS (
                  SELECT 1 FROM active_storage_attachments a
                  WHERE a.record_type = 'JobTask' AND a.record_id = t.id
                    AND NOT EXISTS (
                      SELECT 1 FROM active_storage_attachments pa
                      WHERE pa.record_type = 'PrintOrder' AND pa.record_id = jo.legacy_print_order_id
                        AND pa.blob_id = a.blob_id
                        AND a.name = CASE pa.name WHEN 'file' THEN 'user_files' ELSE 'staff_files' END
                    )
                )
              )
            )
          )
        ) THEN
          RAISE EXCEPTION 'imported print orders were changed after the import (extra tasks, quotes, statuses, options, files, line items, chat messages or services); nothing was removed';
        END IF;
      END $$
    SQL
    execute <<~SQL
      DELETE FROM active_storage_attachments a
      USING job_tasks t, job_orders jo
      WHERE a.record_type = 'JobTask' AND t.id = a.record_id AND jo.id = t.job_order_id
        AND jo.legacy_print_order_id IS NOT NULL
    SQL
    execute <<~SQL
      DELETE FROM job_task_quotes WHERE job_task_id IN (
        SELECT t.id FROM job_tasks t JOIN job_orders jo ON jo.id = t.job_order_id
        WHERE jo.legacy_print_order_id IS NOT NULL)
    SQL
    execute <<~SQL
      DELETE FROM job_tasks WHERE job_order_id IN (SELECT id FROM job_orders WHERE legacy_print_order_id IS NOT NULL)
    SQL
    execute <<~SQL
      DELETE FROM job_order_statuses WHERE job_order_id IN (SELECT id FROM job_orders WHERE legacy_print_order_id IS NOT NULL)
    SQL
    execute "DELETE FROM job_orders WHERE legacy_print_order_id IS NOT NULL"
  end
end
