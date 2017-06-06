class AddTrainingSessionIdToCertifications < ActiveRecord::Migration
  def change
    add_column :certifications, :training_session_id, :string
  end
end
