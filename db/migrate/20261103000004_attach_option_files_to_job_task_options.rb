# Files attached to an order's options (JobOrderOption, "option_file") were never attached
# to the matching job_task_options. Each gets a JobTaskOption "option_file" attachment on
# the same blob (no file is copied), matched by order and job_option_id. A file is attached
# only when exactly one task option of the order has that option and that task option has no
# option file yet; any other file is left for a manual decision. The old attachment rows stay.
class AttachOptionFilesToJobTaskOptions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      SELECT 'option_file', 'JobTaskOption', m.task_option_id, m.blob_id, a_created_at
      FROM (
        SELECT a.blob_id, a.created_at AS a_created_at, tto.id AS task_option_id,
               COUNT(*) OVER (PARTITION BY a.id) AS candidates
        FROM active_storage_attachments a
        JOIN job_order_options oo ON oo.id = a.record_id
        JOIN job_tasks t ON t.job_order_id = oo.job_order_id
        JOIN job_task_options tto ON tto.job_task_id = t.id AND tto.job_option_id = oo.job_option_id
        WHERE a.record_type = 'JobOrderOption' AND a.name = 'option_file'
      ) m
      WHERE m.candidates = 1
        AND NOT EXISTS (
          SELECT 1 FROM active_storage_attachments b
          WHERE b.record_type = 'JobTaskOption' AND b.name = 'option_file' AND b.record_id = m.task_option_id
        )
    SQL
  end

  def down
    # Precise: only the attachments this migration could have made, i.e. a JobTaskOption file
    # whose blob is also the file of the old option row it was matched from.
    execute <<~SQL
      DELETE FROM active_storage_attachments b
      USING active_storage_attachments a, job_order_options oo, job_tasks t, job_task_options tto
      WHERE b.record_type = 'JobTaskOption' AND b.name = 'option_file'
        AND a.record_type = 'JobOrderOption' AND a.name = 'option_file' AND a.blob_id = b.blob_id
        AND oo.id = a.record_id
        AND t.job_order_id = oo.job_order_id
        AND tto.job_task_id = t.id AND tto.job_option_id = oo.job_option_id AND tto.id = b.record_id
    SQL
  end
end
