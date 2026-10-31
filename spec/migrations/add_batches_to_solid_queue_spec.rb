require "rails_helper"
require Rails.root.join("db/queue_migrate/20260906182502_add_batches_to_solid_queue")

# The queue tables live in the queue database, not in the test one, so this
# builds a minimal solid_queue_jobs to run the migration against. CREATE INDEX
# CONCURRENTLY cannot run in a transaction: scratch tables are dropped after
# every example, however it ends.
RSpec.describe AddBatchesToSolidQueue do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:tables) { %i[solid_queue_batch_executions solid_queue_batches solid_queue_jobs] }

  def run(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def job_indexes
    conn.indexes(:solid_queue_jobs).map(&:name)
  end

  before do
    tables.each { |t| conn.drop_table(t, if_exists: true) }
    conn.create_table(:solid_queue_jobs) { |t| t.string :class_name }
  end

  after { tables.each { |t| conn.drop_table(t, if_exists: true) } }

  it "up, up again: builds the batch_id index once and is safe to re-run" do
    run(:up)
    expect(job_indexes).to eq(%w[index_solid_queue_jobs_on_batch_id])
    expect(conn.table_exists?(:solid_queue_batches)).to be(true)
    expect { run(:up) }.not_to raise_error
    expect(job_indexes).to eq(%w[index_solid_queue_jobs_on_batch_id])
  end

  it "down is irreversible and leaves everything in place" do
    run(:up)
    expect { run(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /queue_schema\.rb/)
    expect(conn.table_exists?(:solid_queue_batches)).to be(true)
    expect(conn.column_exists?(:solid_queue_jobs, :batch_id)).to be(true)
    expect(job_indexes).to eq(%w[index_solid_queue_jobs_on_batch_id])
  end
end
