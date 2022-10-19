class CreateUserBookingApprovals < ActiveRecord::Migration[6.1]
  def change
    create_table :user_booking_approvals do |t|
      t.references :user, null: false, foreign_key: true
      t.date :date
      t.string :comments
      t.references :staff, foreign_key: { to_table: :users }, optional: true
      t.boolean :approved

      t.timestamps
    end
  end
end
