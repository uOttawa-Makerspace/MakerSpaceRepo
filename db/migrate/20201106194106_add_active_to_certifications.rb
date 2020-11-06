class AddActiveToCertifications < ActiveRecord::Migration[6.0]
  def change
    add_column :certifications, :active, :boolean, default: true
  end
end
