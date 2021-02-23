class AddDemotionStaffToCertifications < ActiveRecord::Migration[6.0]
  def change
    add_reference :certifications, :demotion_staff
    add_foreign_key :certifications, :users, column: :demotion_staff_id
  end
end
