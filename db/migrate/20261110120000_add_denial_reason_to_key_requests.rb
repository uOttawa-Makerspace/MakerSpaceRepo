# Adds the reason an admin gives when denying a key request. The column is nullable and no
# existing row is changed. The new "denied" status is appended to the status enum, so the stored
# integers of the existing statuses stay the same.
#
# down drops the column only while it holds nothing that exists nowhere else: no denied request
# (status 3, which the old code cannot read) and no stored reason. Otherwise it stops, naming the
# counts, and changes nothing.
class AddDenialReasonToKeyRequests < ActiveRecord::Migration[8.1]
  DENIED_STATUS = 3

  def up
    add_column :key_requests, :denial_reason, :text
  end

  def down
    denied = select_value("SELECT COUNT(*) FROM key_requests WHERE status = #{DENIED_STATUS}").to_i
    reasons = select_value("SELECT COUNT(*) FROM key_requests WHERE denial_reason IS NOT NULL").to_i
    if denied.positive? || reasons.positive?
      raise ActiveRecord::IrreversibleMigration,
            "Not rolled back: #{denied} denied key requests and #{reasons} stored denial reasons would be lost. " \
            "Export them and clear them first."
    end

    remove_column :key_requests, :denial_reason
  end
end
