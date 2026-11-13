require "rails_helper"
require Rails.root.join("db/migrate/20261113110000_change_memberships_status_default_to_pending")

# DDL is transactional in the test database, so each example puts the old default back first and the rollback
# restores the real schema afterwards.
RSpec.describe ChangeMembershipsStatusDefaultToPending do
  let(:connection) { ActiveRecord::Base.connection }

  before { connection.change_column_default(:memberships, :status, "paid") }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def column_default
    connection.columns(:memberships).find { |c| c.name == "status" }.default
  end

  def insert_without_status(user)
    id = connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO memberships (user_id, membership_tier_id, created_at, updated_at) VALUES (?, ?, now(), now()) " \
         "RETURNING id", user.id, create(:membership_tier).id]
      )
    )
    connection.select_value("SELECT status FROM memberships WHERE id = #{Integer(id)}")
  end

  it "makes the column default pending and leaves every existing row as it was" do
    rows = %w[paid pending revoked].map { |status| create(:membership, status: status) }
    expect(column_default).to eq("paid")

    expect { migrate }.not_to change(Membership, :count)

    expect(column_default).to eq("pending")
    expect(rows.map { |row| row.reload.status }).to eq(%w[paid pending revoked])
    expect(insert_without_status(create(:user))).to eq("pending")
  end

  it "rolls back to the paid default without touching rows, and runs again" do
    row = create(:membership, status: "pending")
    migrate

    expect { migrate(:down) }.not_to change(Membership, :count)

    expect(column_default).to eq("paid")
    expect(row.reload.status).to eq("pending")
    migrate
    expect(column_default).to eq("pending")
  end
end
