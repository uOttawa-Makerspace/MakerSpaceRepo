class AddLockerFieldsAndRentalContacted < ActiveRecord::Migration[8.1]
  def change
    # Add notes to lockers so admins can leave notes on unassigned lockers
    add_column :lockers, :notes, :text unless column_exists?(:lockers, :notes)
    
    # Add audience to lockers to split filtering between 'staff', 'gng' (design class), and 'general'
    add_column :lockers, :audience, :string, default: 'general' unless column_exists?(:lockers, :audience)
    
    # Add contacted checkbox to locker rentals to track if staff emailed users to clear the locker
    add_column :locker_rentals, :contacted_for_clearance, :boolean, default: false, null: false unless column_exists?(:locker_rentals, :contacted_for_clearance)
  end
end