class AddBookingApprovalToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :booking_approval, :boolean, default: false
    User.unscoped.update_all(booking_approval: false)
  end
end
