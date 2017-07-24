class EditCertificationModel < ActiveRecord::Migration
  def change
    remove_column :certifications, :training_name, :string
    add_column :certifications, :training, :string
    add_column :certifications, :trainer_id, :string
  end
end
