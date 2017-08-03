class EditCertificationTraingIdToTrainingName < ActiveRecord::Migration
  def change
    remove_column :certifications, :training_id, :string
    add_column :certifications, :training_name, :string
  end
end
