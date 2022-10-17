class AddBookingApprovalDefaultToAdmins < ActiveRecord::Migration[6.1]
  def up
    User
      .where(role: "admin")
      .each { |user| user.update(booking_approval: true) }
  end
end
