class DropBadgeTemplates < ActiveRecord::Migration[7.2]
  def up
    drop_table :badge_templates
  end

  def down
    create_table :badge_templates do |t|
      t.text :badge_id
      t.text :badge_description
      t.text :badge_name

      t.timestamps null: false
    end
  end
end
