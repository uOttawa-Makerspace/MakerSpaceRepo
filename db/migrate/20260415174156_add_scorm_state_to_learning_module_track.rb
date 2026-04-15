class AddScormStateToLearningModuleTrack < ActiveRecord::Migration[8.1]
  def change
    add_column :learning_module_tracks, :scorm_state, :jsonb
  end
end
