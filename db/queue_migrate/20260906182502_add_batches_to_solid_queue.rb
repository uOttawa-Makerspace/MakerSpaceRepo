class AddBatchesToSolidQueue < ActiveRecord::Migration[7.1]
  # The batch_id index is built CONCURRENTLY so a large solid_queue_jobs keeps
  # accepting inserts, which cannot run inside a transaction. Every statement
  # below is therefore safe to re-run after a partial failure.
  disable_ddl_transaction!

  def change
    # Fresh installs create all of this with the base schema, so skip
    # anything that already exists
    add_column :solid_queue_jobs, :batch_id, :bigint, if_not_exists: true

    # An interrupted concurrent build leaves an INVALID index that
    # if_not_exists would skip; drop it so it is rebuilt.
    reversible do |dir|
      dir.up do
        invalid = select_value(<<~SQL.squish)
          SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
          WHERE c.relname = 'index_solid_queue_jobs_on_batch_id'
            AND c.relnamespace = current_schema()::regnamespace
            AND NOT i.indisvalid
        SQL
        remove_index :solid_queue_jobs, name: "index_solid_queue_jobs_on_batch_id", algorithm: :concurrently if invalid
      end
    end
    add_index :solid_queue_jobs, :batch_id, algorithm: :concurrently, if_not_exists: true

    create_table :solid_queue_batches, if_not_exists: true do |t|
      t.string :active_job_batch_id
      t.string :description
      t.text :on_finish
      t.text :on_success
      t.text :on_failure
      t.text :metadata
      t.integer :total_jobs, default: 0, null: false
      t.integer :completed_jobs, default: 0, null: false
      t.integer :failed_jobs, default: 0, null: false
      t.datetime :enqueued_at
      t.datetime :finished_at
      t.datetime :failed_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index :active_job_batch_id, unique: true
      t.index :finished_at
    end

    create_table :solid_queue_batch_executions, if_not_exists: true do |t|
      t.bigint :job_id, null: false
      t.bigint :batch_id, null: false
      t.datetime :created_at, null: false

      t.index :job_id, unique: true
      t.index :batch_id
      t.foreign_key :solid_queue_batches, column: :batch_id, on_delete: :cascade
      t.foreign_key :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
  end
end
