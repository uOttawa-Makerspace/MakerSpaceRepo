class AddTrainingIdToBadgeTemplate < ActiveRecord::Migration[6.0]
  def change
    add_reference :badge_templates, :training, index: true, foreign_key: true
  end
end
