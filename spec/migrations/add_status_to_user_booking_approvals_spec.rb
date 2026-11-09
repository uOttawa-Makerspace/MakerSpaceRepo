require "rails_helper"
require Rails.root.join("db/migrate/20261109120000_add_status_to_user_booking_approvals")

# DDL is transactional in PostgreSQL, so each example takes the columns off, writes rows in the old
# shape with SQL and runs the migration inside the example's transaction; everything rolls back.
RSpec.describe AddStatusToUserBookingApprovals do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:new_columns) { %w[status decided_by_id decided_at reason] }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }
    UserBookingApproval.reset_column_information
  end

  def insert(approved:, staff_id: nil, identity: "Other")
    connection.select_value(<<~SQL.squish)
      INSERT INTO user_booking_approvals (user_id, staff_id, approved, identity, comments, date, created_at, updated_at)
      VALUES (#{user.id}, #{staff_id || 'NULL'}, #{connection.quote(approved)}, #{connection.quote(identity)},
              'why', '2026-01-05', '2026-01-05 10:00', '2026-01-06 11:00')
      RETURNING id
    SQL
  end

  def rows
    connection.select_rows("SELECT * FROM user_booking_approvals ORDER BY id")
  end

  def old_columns
    connection.select_rows(
      "SELECT id, user_id, staff_id, approved, identity, comments, date, created_at, updated_at " \
      "FROM user_booking_approvals ORDER BY id"
    )
  end

  def statuses
    connection.select_rows("SELECT id, status FROM user_booking_approvals ORDER BY id").to_h
  end

  # Rows in the old shape (no status columns): one pending, one approved, one approved without an identity.
  def old_shape_rows
    migrate(:down)
    { pending: insert(approved: false), approved: insert(approved: true, staff_id: staff.id),
      no_identity: insert(approved: true, staff_id: staff.id, identity: nil) }
  end

  it "sets each row's status from approved and leaves every old column as it was" do
    ids = old_shape_rows
    before = old_columns

    migrate(:up)

    expect(statuses).to eq(ids[:pending] => "pending", ids[:approved] => "approved", ids[:no_identity] => "approved")
    expect(old_columns).to eq(before)
    expect(connection.select_values("SELECT decided_by_id FROM user_booking_approvals").uniq).to eq([nil])
    expect(connection.indexes(:user_booking_approvals).map(&:columns)).to include(["status"], ["decided_by_id"])
    fk = connection.foreign_keys(:user_booking_approvals).find { |key| key.column == "decided_by_id" }
    expect([fk.to_table, fk.on_delete]).to eq(["users", :nullify])
  end

  it "refuses a status outside the four" do
    old_shape_rows
    migrate(:up)
    expect { connection.execute("UPDATE user_booking_approvals SET status = 'lost'") }
      .to raise_error(ActiveRecord::StatementInvalid, /user_booking_approvals_status_check/)
  end

  it "goes down to exactly the old rows" do
    old_shape_rows
    before = rows
    migrate(:up)

    migrate(:down)

    expect(new_columns.map { |column| connection.column_exists?(:user_booking_approvals, column) }.uniq).to eq([false])
    expect(rows).to eq(before)
  end

  it "comes up again the same way after going down" do
    old_shape_rows
    migrate(:up)
    first = statuses
    migrate(:down)
    migrate(:up)
    expect(statuses).to eq(first)
  end

  {
    "a declined row" => ["status = 'declined', approved = false", "1 declined or revoked"],
    "a revoked row" => ["status = 'revoked', approved = false", "1 declined or revoked"],
    "a recorded decided_at" => ["decided_at = now()", "1 with a decided_at"],
    "a recorded reason" => ["reason = 'no'", "1 with a reason"],
    "a status that differs from approved" => ["status = 'approved'", "1 whose status differs from approved"]
  }.each do |what, (change, message)|
    it "refuses to go down while #{what} exists, and changes nothing" do
      ids = old_shape_rows
      migrate(:up)
      connection.execute("UPDATE user_booking_approvals SET #{change} WHERE id = #{ids[:pending]}")
      before = rows

      expect { migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /#{message}/)
      expect(rows).to eq(before)
    end
  end

  it "refuses to go down while a decided_by is recorded" do
    ids = old_shape_rows
    migrate(:up)
    connection.execute("UPDATE user_booking_approvals SET decided_by_id = #{staff.id} WHERE id = #{ids[:approved]}")

    expect { migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /1 with a decided_by/)
    expect(connection.column_exists?(:user_booking_approvals, :status)).to be(true)
  end
end
