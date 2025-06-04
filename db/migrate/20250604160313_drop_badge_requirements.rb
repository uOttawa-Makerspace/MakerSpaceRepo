class DropBadgeRequirements < ActiveRecord::Migration[7.2]
  def up
    drop_table :badge_requirements
  end

  def down
    create_table :badge_requirements do |t|
      t.timestamps null: false
      t.references :badge_template, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
    end
  end
end
