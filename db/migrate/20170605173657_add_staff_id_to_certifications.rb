class AddStaffIdToCertifications < ActiveRecord::Migration
  def change
    add_column :certifications, :staff_id, :string
  end
end
