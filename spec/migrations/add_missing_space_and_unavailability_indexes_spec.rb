require "rails_helper"
require Rails.root.join("db/migrate/20261030140000_add_missing_space_and_unavailability_indexes")

# CREATE/DROP INDEX CONCURRENTLY cannot run in a transaction, so this spec runs
# outside the transactional wrapper and restores the schema's index set after.
RSpec.describe AddMissingSpaceAndUnavailabilityIndexes do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }

  def names(table)
    conn.indexes(table).map(&:name).sort
  end

  def run(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  AFTER_UP = {
    events: %w[idx_events_on_space_and_draft idx_events_on_space_and_times index_events_on_course_name_id
               index_events_on_created_by_id index_events_on_training_id],
    staff_spaces: %w[idx_staff_spaces_space_user index_staff_spaces_on_user_id],
    staff_unavailabilities: %w[index_staff_unavailabilities_on_user_id]
  }.freeze

  AFTER_DOWN = {
    events: %w[index_events_on_course_name_id index_events_on_created_by_id index_events_on_space_id index_events_on_training_id],
    staff_spaces: %w[index_staff_spaces_on_space_id index_staff_spaces_on_user_id],
    staff_unavailabilities: %w[index_staff_unavailabilities_on_user_id]
  }.freeze

  def expect_indexes(expected)
    expected.each { |table, list| expect(names(table)).to eq(list.sort), "indexes on #{table}" }
  end

  # Leave the DB as schema.rb defines it, however the example ended: even if
  # `down` raised partway, `up` is idempotent and converges on the schema's set.
  # The leftover idx_staff_unavail_user_times of one example is dropped by `up`.
  after { run(:up) }

  it "up, down, up: exactly the schema.rb index set, then the single-column set, then again" do
    run(:up)
    expect_indexes(AFTER_UP)
    run(:down)
    expect_indexes(AFTER_DOWN)
    run(:up)
    expect_indexes(AFTER_UP)
  end

  it "drops a leftover idx_staff_unavail_user_times from a database that loaded the old dumped schema, and down does not recreate it" do
    conn.add_index :staff_unavailabilities, %i[user_id start_time end_time], name: "idx_staff_unavail_user_times"
    run(:up)
    expect_indexes(AFTER_UP)
    run(:down)
    expect(names(:staff_unavailabilities)).to eq(%w[index_staff_unavailabilities_on_user_id])
  end

  it "builds over an existing valid copy of its indexes without error" do
    run(:up)
    expect { run(:up) }.not_to raise_error
    expect_indexes(AFTER_UP)
  end
end
