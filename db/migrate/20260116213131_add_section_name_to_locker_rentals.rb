class AddSectionNameToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_reference :locker_rentals, :course_name
    add_column :locker_rentals, :section_name, :string
    add_column :locker_rentals, :team_name, :string
  end
end
