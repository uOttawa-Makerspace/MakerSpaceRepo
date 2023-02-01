class CreateSubSpaceBookings < ActiveRecord::Migration[6.1]
  def change
    create_table :sub_space_bookings do |t|
      t.string :name
      t.string :description
      t.datetime :start_time
      t.datetime :end_time
      t.belongs_to :user, foreign_key: true
      t.belongs_to :sub_space, foreign_key: true

      t.timestamps
    end
  end
end
