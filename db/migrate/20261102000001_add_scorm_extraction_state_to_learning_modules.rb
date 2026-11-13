# When the current SCORM extraction state was entered (an extraction stuck in
# pending/processing is judged against it) and, for a failed one, why. Both NULL
# for existing rows; a pending/processing row with no time counts as stalled.
class AddScormExtractionStateToLearningModules < ActiveRecord::Migration[8.1]
  def change
    add_column :learning_modules, :scorm_status_changed_at, :datetime
    add_column :learning_modules, :scorm_error, :string
  end
end
