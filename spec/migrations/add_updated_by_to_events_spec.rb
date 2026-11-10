# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261110100000_add_updated_by_to_events")

# events.updated_by_id records the last editor. Up adds an empty column with an index and a key to users
# (no cascade), changing no existing row; down removes it only while it is empty.
RSpec.describe AddUpdatedByToEvents do
  let(:connection) { ActiveRecord::Base.connection }
  let(:space) { create(:space) }
  let(:creator) { create(:user, :staff) }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    Event.reset_column_information
  end

  def column? = connection.column_exists?(:events, :updated_by_id)

  def checksum
    connection.select_rows("SELECT id, created_by_id, updated_at FROM events ORDER BY id")
  end

  before { migrate(:down) }

  it "adds a nullable, indexed column keyed to users and leaves every row as it was" do
    create(:event, space: space, created_by: creator)
    before_rows = checksum

    migrate(:up)

    column = connection.columns(:events).find { |c| c.name == "updated_by_id" }
    expect(column.null).to be(true)
    expect(connection.index_exists?(:events, :updated_by_id)).to be(true)
    key = connection.foreign_keys(:events).find { |k| k.column == "updated_by_id" }
    expect(key).to have_attributes(to_table: "users", on_delete: nil)
    expect(checksum).to eq(before_rows)
    expect(connection.select_value("SELECT COUNT(*) FROM events WHERE updated_by_id IS NOT NULL")).to eq(0)
  end

  it "goes down when no editor is recorded, restoring the rows exactly" do
    create(:event, space: space, created_by: creator)
    migrate(:up)
    before_rows = checksum

    migrate(:down)

    expect(column?).to be(false)
    expect(checksum).to eq(before_rows)
  end

  it "refuses to go down while an event records an editor, and changes nothing" do
    migrate(:up)
    create(:event, space: space, created_by: creator, updated_by: creator)

    expect { migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /1 events record who last edited/)
    expect(column?).to be(true)
  end

  it "can go up again after going down" do
    migrate(:up)
    migrate(:down)
    migrate(:up)
    expect(column?).to be(true)
  end
end
