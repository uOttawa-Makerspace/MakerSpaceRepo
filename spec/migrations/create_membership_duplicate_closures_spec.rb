# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115150000_create_membership_duplicate_closures")

# The table holds the record of each membership the duplicate cleanup marked failed, so rolling back must never drop
# recorded rows. Runs inside the example's transaction (the migration is plain DDL), so every change is rolled back.
RSpec.describe CreateMembershipDuplicateClosures do
  let(:conn) { ActiveRecord::Base.connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def record!
    older, kept = create_list(:membership, 2, status: "failed")
    Membership::DuplicateClosure.create!(membership: older, kept_membership: kept, previous_status: "pending",
                                         previous_updated_at: Time.current, marked_updated_at: Time.current)
  end

  it "refuses to roll back while a change is recorded, keeping the table and its rows" do
    record!

    expect { migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /records 1 closed membership/)
    expect(Membership::DuplicateClosure.count).to eq(1)
  end

  it "rolls back when nothing is recorded and builds the table again" do
    migrate(:down)
    expect(conn.table_exists?(:membership_duplicate_closures)).to be(false)

    migrate(:up)
    Membership::DuplicateClosure.reset_column_information
    expect(conn.indexes(:membership_duplicate_closures).find { |i| i.columns == ["membership_id"] })
      .to have_attributes(unique: true, where: "(restored_at IS NULL)")
    expect(conn.foreign_keys(:membership_duplicate_closures)).to be_empty
    expect { record! }.to change(Membership::DuplicateClosure, :count).by(1)
  end

  it "refuses a second open record for the same membership, and outlives a deleted membership" do
    closure = record!

    expect { Membership::DuplicateClosure.create!(closure.attributes.except("id")) }.to raise_error(ActiveRecord::RecordNotUnique)
    closure.update_columns(restored_at: Time.current)
    expect { Membership::DuplicateClosure.create!(closure.attributes.except("id", "restored_at")) }.not_to raise_error
    Membership.where(id: [closure.membership_id, closure.kept_membership_id]).delete_all
    expect(Membership::DuplicateClosure.where(id: closure.id)).to exist
  end
end
