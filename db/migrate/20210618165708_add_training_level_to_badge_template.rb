class AddTrainingLevelToBadgeTemplate < ActiveRecord::Migration[6.0]
  def change
    add_column :badge_templates, :training_level, :string
  end
end
