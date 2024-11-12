class CreateStaffAvailabilityExceptions < ActiveRecord::Migration[7.0]
  def change
    create_table :staff_availability_exceptions do |t|
      t.belongs_to :staff_availability
      t.datetime :start_at
      t.integer :type, default: 0
    end
  end
end
