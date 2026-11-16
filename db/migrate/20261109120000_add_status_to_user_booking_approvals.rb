# Booking access requests keep a status instead of being deleted when they are declined or revoked:
# pending, approved, declined or revoked, with who decided (decided_by_id), when (decided_at) and
# why (reason). Nothing is moved: the `approved` and `staff_id` columns stay as they are, and the
# model keeps `approved` equal to (status = 'approved').
#
# up adds the columns and sets each existing row's status from `approved` (true -> approved, any
# other value -> pending, which is how the pending list read them). Existing rows get no
# decided_by, decided_at or reason: the approver of an approved row stays in staff_id.
#
# down removes the new columns only while they hold nothing that exists nowhere else: no declined
# or revoked row, no recorded decided_by, decided_at or reason, and every status still equal to
# what `approved` says. Otherwise it stops, naming the counts, and changes nothing.
class AddStatusToUserBookingApprovals < ActiveRecord::Migration[8.1]
  STATUSES = %w[pending approved declined revoked].freeze

  def up
    add_column :user_booking_approvals, :status, :string, null: false, default: "pending"
    add_reference :user_booking_approvals, :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :user_booking_approvals, :decided_at, :datetime
    add_column :user_booking_approvals, :reason, :text
    add_check_constraint :user_booking_approvals, status_check, name: "user_booking_approvals_status_check"
    add_index :user_booking_approvals, :status

    execute "UPDATE user_booking_approvals SET status = 'approved' WHERE approved = true"
  end

  def down
    refuse_if_information_would_be_lost

    remove_index :user_booking_approvals, :status
    remove_check_constraint :user_booking_approvals, name: "user_booking_approvals_status_check"
    remove_column :user_booking_approvals, :reason
    remove_column :user_booking_approvals, :decided_at
    remove_reference :user_booking_approvals, :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }
    remove_column :user_booking_approvals, :status
  end

  private

  def status_check
    "status IN (#{STATUSES.map { |status| connection.quote(status) }.join(', ')})"
  end

  def refuse_if_information_would_be_lost
    counts = {
      "declined or revoked" => "status IN ('declined', 'revoked')",
      "with a decided_by" => "decided_by_id IS NOT NULL",
      "with a decided_at" => "decided_at IS NOT NULL",
      "with a reason" => "reason IS NOT NULL",
      "whose status differs from approved" => "(status = 'approved') IS DISTINCT FROM COALESCE(approved, false)"
    }.transform_values { |condition| select_value("SELECT COUNT(*) FROM user_booking_approvals WHERE #{condition}").to_i }
    found = counts.select { |_, count| count.positive? }
    return if found.empty?

    raise ActiveRecord::IrreversibleMigration,
          "Not going down: these user_booking_approvals rows hold information that exists nowhere else: " \
          "#{found.map { |what, count| "#{count} #{what}" }.join(', ')}. Copy it elsewhere first."
  end
end
