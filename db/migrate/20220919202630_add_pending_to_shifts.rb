class AddPendingToShifts < ActiveRecord::Migration[6.1]
  def up
    add_column :shifts, :pending, :boolean, default: true
    Shift.update_all(pending: false)
  end

  def down
    remove_column :shifts, :pending
  end
end
