# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115130100_require_user_and_space_on_space_manager_joins")

# DDL is transactional in the test database, so each example makes both columns nullable first and the rollback
# restores the real schema afterwards.
RSpec.describe RequireUserAndSpaceOnSpaceManagerJoins do
  let(:conn) { ActiveRecord::Base.connection }
  let(:admin) { create(:user, :admin) }
  let(:space) { create(:space) }

  before do
    described_class::COLUMNS.each { |column| conn.change_column_null(:space_manager_joins, column, true) }
    SpaceManagerJoin.reset_column_information
  end

  after { SpaceManagerJoin.reset_column_information }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(user_id: admin.id, space_id: space.id)
    now = Time.current
    conn.transaction(requires_new: true) do
      SpaceManagerJoin.insert_all!([{ user_id: user_id, space_id: space_id, created_at: now, updated_at: now }])
    end
  end

  def nullable
    conn.columns(:space_manager_joins).select { |c| %w[user_id space_id].include?(c.name) }.to_h { |c| [c.name, c.null] }
  end

  def rows = conn.select_rows("SELECT id, user_id, space_id FROM space_manager_joins ORDER BY id")

  it "refuses while rows lack a user or a space, naming the counts, and changes nothing" do
    insert(user_id: nil)
    insert(user_id: nil, space_id: create(:space).id)
    insert(space_id: nil)
    insert
    before_rows = rows

    expect { migrate }.to raise_error(RuntimeError, /2 with no user_id, 1 with no space_id\. Nothing was changed/)
    expect(nullable).to eq("user_id" => true, "space_id" => true)
    expect(rows).to eq(before_rows)
  end

  it "makes the database refuse a row without a user or a space afterwards" do
    insert
    migrate

    expect(nullable).to eq("user_id" => false, "space_id" => false)
    expect(SpaceManagerJoin.count).to eq(1)
    expect { insert(user_id: nil, space_id: create(:space).id) }.to raise_error(ActiveRecord::NotNullViolation)
    expect { insert(space_id: nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "rolls back to nullable columns, keeping every row, and runs again" do
    insert
    migrate
    before_rows = rows
    migrate(:down)

    expect(nullable).to eq("user_id" => true, "space_id" => true)
    expect(rows).to eq(before_rows)
    expect { migrate }.not_to raise_error
    expect(nullable).to eq("user_id" => false, "space_id" => false)
  end
end
