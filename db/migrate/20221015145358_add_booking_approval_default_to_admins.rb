class AddBookingApprovalDefaultToAdmins < ActiveRecord::Migration[6.1]
  def change
    User
      .where(role: "admin")
      .each { |user| user.update(booking_approval: true) }
  end
end
