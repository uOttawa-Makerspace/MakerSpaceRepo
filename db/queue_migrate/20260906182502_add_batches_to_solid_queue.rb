require Rails.root.join("lib/concurrent_index_builder")

class AddBatchesToSolidQueue < ActiveRecord::Migration[7.1]
  # The batch_id index is built CONCURRENTLY so a large solid_queue_jobs keeps
  # accepting inserts, which cannot run inside a transaction; every statement
  # is therefore safe to re-run, and an INVALID leftover index is rebuilt.
  # This edit never ran in production, and staging's earlier non-concurrent
  # build already produced a valid index, so nothing is needed there.
  disable_ddl_transaction!
  include ConcurrentIndexBuilder

  # On a fresh install the base schema already has the batch_id column and
  # index and the batch tables, so `up` skips what exists and `down` is
  # irreversible: it cannot tell which objects this migration created.
  def up
    add_column :solid_queue_jobs, :batch_id, :bigint, if_not_exists: true
    add_index_concurrently :solid_queue_jobs, :batch_id, name: "index_solid_queue_jobs_on_batch_id"

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

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the batch tables and solid_queue_jobs.batch_id may come from queue_schema.rb on a fresh install, " \
          "not from this migration, so dropping them could destroy data this migration never created"
  end
end
