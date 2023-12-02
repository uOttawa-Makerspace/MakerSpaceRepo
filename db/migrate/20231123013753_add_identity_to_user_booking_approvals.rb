class AddIdentityToUserBookingApprovals < ActiveRecord::Migration[7.0]
  def change
    add_column :user_booking_approvals, :identity, :string, default: nil
  end
end
